local Stack = require("Stack")

--[[ 
响应式系统
    1. 响应式对象：proxyTable，实质为Proxy代理，劫持get和set操作
    2. 计算属性：computedTable，实质为Computed代理，劫持get和set操作
    3. 副作用函数：effect，和proxyTable绑定，当proxyTable的属性发生变化时，通知effect重新执行
    4. 依赖收集：副作用函数依赖响应式对象，计算属性依赖响应式对象, 计算属性依赖计算属性
    5. 计算属性懒计算：访问计算属性时，如果有缓存则直接返回，否则调用getter重新计算
                      当计算属性依赖的响应式对象发生变化时，清除缓存
--]]

local ReactiveSystem = {
    --[[ 
        副作用函数表: effects为副作用函数，key为proxyTable，value为key对应的副作用函数列表
        设计模式：观察者模式/发布订阅模式
        数据结构：
        { 
            proxyTable1 = { 
                key1 = { effect1, effect2, ... }, 
                key2 = { effect3, effect4, ... },
                ...
            },
            proxyTable2 = { 
                key3 = { effect5, effect6, ... }, 
                key4 = { effect7, effect8, ... },
                ...
            },
            ...
        }
    --]]
    effects = {},           

    --[[
        计算属性缓存: computedTable为计算属性，本质是一个代理表，key固定为"value"，value为计算属性的值
        为实现懒计算而设计出的一个全局缓存表
        数据结构：
        { 
            computedTable1 = value1, 
            computedTable2 = value2, 
            ... 
        }
    --]]
    caches = {},

    --[[
        直接依赖关系表: deps为所有计算属性的依赖关系表，用于依赖收集
        结构理解：计算属性直接依赖的可能是响应式对象，也可能是计算属性；
                以被依赖的对象为一级key，以被依赖的对象的key为二级key，value为依赖这个对象属性的计算属性列表
                每当有计算属性或响应式对象发生变化时，将依赖这个对象的计算属性缓存清除；
        如何建立依赖关系：在首次访问计算属性时，将计算属性对象压入栈中，
                        然后递归访问计算属性的依赖关系，直到访问到响应式对象
        数据结构：
        { 
            proxyTable1 = {
                key1 = {computedTable1, computedTable2, ...},
                key2 = {computedTable3, computedTable4, ...},
                ...
            },
            computedTable1 = {
                ["value"] = {computedTable5, computedTable6, ...},
            },
            computedTable2 = {
                ["value"] = {computedTable5, computedTable7, ...},
            },
            ... 
        }
    --]]
    deps = {}
}

-- 前置声明
local isRef = nil           -- 是否是Ref对象
local isReactive = nil      -- 是否是Reactive对象
local isComputed = nil      -- 是否是计算属性

local reactive = nil        -- 创建Reactive对象
local ref = nil             -- 创建Ref对象

local computed = nil        -- 创建计算属性
local clearComputed = nil   -- 清理计算属性

local watch = nil           -- 监视响应式数据变化
local unwatch = nil         -- 取消监视

local watchRef = nil        -- 监视Ref对象的变化
local watchComputed = nil   -- 监视计算属性的变化
local watchReactive = nil   -- 监视Reactive对象的变化

-- 副作用函数指针，用于绑定与之关联的响应式对象
local effectFuncPtr = nil

-- 计算属性栈，用于临时存储计算属性对象
local computedTableStack = Stack.new()

-- 代理类
local Proxy = {}
Proxy.__index = function(proxyTable, key)
    if key == "_real" then
        return rawget(proxyTable._real, key)
    end

    -- 检测是否有副作用函数绑定
    if effectFuncPtr then
        ReactiveSystem:subscribe(proxyTable, key, effectFuncPtr)
    end

    -- 建立依赖关系
    ReactiveSystem:buildDeps(proxyTable, key, computedTableStack:top())

    return rawget(proxyTable._real, key)
end
Proxy.__newindex = function(proxyTable, key, value)
    -- 递归创建Reactive对象
    if type(value) == "table" then
        if not isReactive(value) then
            value = reactive(value)
        end
    end

    local oldValue = rawget(proxyTable._real, key)

    -- 当数据发生变化时
    if oldValue ~= value then
        rawset(proxyTable._real, key, value)

        -- 触发依赖关系，清除所有依赖proxyTable的计算属性的缓存
        ReactiveSystem:triggerDeps(proxyTable, key)

        -- 通知与之绑定的副作用函数重新执行
        ReactiveSystem:publish(proxyTable, key, oldValue) 
    end
end

-- 创建代理对象
function Proxy.new(realTable)
    local proxyTable = {}
    proxyTable._real = realTable or {}
    setmetatable(proxyTable, Proxy)

    ReactiveSystem.deps[proxyTable] = {}
    return proxyTable
end

-- 计算属性类
local Computed = {}
Computed.__index = function(computedTable, key)
    if key == "_real" then
        return rawget(computedTable._real, key)
    end

    -- 计算属性只有一个key，固定为"value"
    if "value" ~= key then
        return nil
    end

    -- 检测绑定副作用函数
    if effectFuncPtr then
        ReactiveSystem:subscribe(computedTable, key, effectFuncPtr)
    end

    -- 建立依赖关系
    ReactiveSystem:buildDeps(computedTable, key, computedTableStack:top())

    -- 调用getter函数之前，先将计算属性对象压入栈中，以便后续建立依赖关系
    if not computedTableStack:hasElement(computedTable) then
        computedTableStack:push(computedTable)
    end

    -- 计算属性懒计算
    if not ReactiveSystem.caches[computedTable] then
        -- getterValueIsNil为true时，表示上一次访问时getter函数返回了nil
        -- 因此本次访问时直接返回nil，无须再调用getter
        if computedTable._real.getterValueIsNil then
            if not computedTableStack:isEmpty() then                
                computedTableStack:pop()
            end

            return nil
        end
       
        -- 调用getter函数
        ReactiveSystem.caches[computedTable] = computedTable._real.getter()

        -- 当计算属性的getter函数返回nil时，标记为true
        computedTable._real.getterValueIsNil = ReactiveSystem.caches[computedTable] == nil
    end

    if not computedTableStack:isEmpty() then
        computedTableStack:pop()
    end

    -- 返回计算属性的值
    return ReactiveSystem.caches[computedTable]
end

Computed.__newindex = function(computedTable, key, value)
    -- 计算属性只有一个key，固定为"value"
    if "value" ~= key then
        return
    end

    -- 更新计算属性的值
    local oldValue = ReactiveSystem.caches[computedTable]
    ReactiveSystem.caches[computedTable] = value

    -- 如果计算数值有setter函数，则调用setter函数
    if computedTable._real.setter then
        computedTable._real.setter(value)
    end

    -- 通知与之绑定的副作用函数重新执行
    if oldValue ~= value then
        ReactiveSystem:triggerDeps(computedTable, key)
        ReactiveSystem:publish(computedTable, key, oldValue)
    end
end

-- 创建计算属性对象
function Computed.new(getter, setter)
    local realTable = {}
    realTable.getter = getter
    realTable.setter = setter

    -- 如果getter函数返回nil，则标记为true，下次访问时直接返回nil，不再调用getter
    realTable.getterValueIsNil = false

    local computedTable = {}
    computedTable._real = realTable

    setmetatable(computedTable, Computed)

    ReactiveSystem.deps[computedTable] = {}
    return computedTable
end

-- 是否是Reactive对象
isReactive = function(obj)
    return getmetatable(obj) == Proxy
end

-- 是否是Ref对象
isRef = function(obj)
    return isReactive(obj) and obj._real and next(obj._real) == "value"
end

-- 是否是计算属性
isComputed = function(obj)
    return getmetatable(obj) == Computed
end

-- 建立依赖关系：firstKey可能是proxyTable，也可能是computedTable
function ReactiveSystem:buildDeps(firstKey, secondKey, targetComputedTable)
    if not targetComputedTable then
        return
    end

    if not self.deps[firstKey] then
        return
    end

    if not self.deps[firstKey][secondKey] then
        self.deps[firstKey][secondKey] = {}
    end

    for _, computedTable in ipairs(self.deps[firstKey][secondKey]) do
        if computedTable == targetComputedTable then
            return
        end
    end

    table.insert(self.deps[firstKey][secondKey], targetComputedTable)
end

-- 递归触发依赖关系：firstKey可能是proxyTable，也可能是computedTable
function ReactiveSystem:triggerDeps(firstKey, secondKey)
    if not self.deps[firstKey] then
        return
    end

    if not self.deps[firstKey][secondKey] then
        return
    end

    if #self.deps[firstKey][secondKey] == 0 then
        return
    end

    for _, computedTable in ipairs(self.deps[firstKey][secondKey]) do
        -- 清除计算属性的缓存
        self.caches[computedTable] = nil

        -- getter返回nil的标记重置为false
        computedTable._real.getterValueIsNil = false

        -- 递归触发依赖关系
        if isComputed(computedTable) then
            self:triggerDeps(computedTable, "value")
        end
    end
end

-- 订阅副作用函数
function ReactiveSystem:subscribe(t, key, effect)
    if not self.effects[t] then
        self.effects[t] = {}
    end

    if not self.effects[t][key] then
        self.effects[t][key] = {}
    end

    for _, v in ipairs(self.effects[t][key]) do
        if v == effect then
            return
        end
    end

    table.insert(self.effects[t][key], effect)
end

-- 取消订阅
function ReactiveSystem:unsubscribe(t, key, effect)
    if not self.effects[t] then
        return
    end

    if not self.effects[t][key] then
        self.effects[t] = nil
        return
    end

    -- 取消key对应的所有订阅
    if not effect then
        self.effects[t][key] = nil
        return
    end

    -- 取消key对应的某个订阅
    for i, v in ipairs(self.effects[t][key]) do
        if v == effect then
            table.remove(self.effects[t][key], i)
            return
        end
    end
end

-- 发布副作用函数
function ReactiveSystem:publish(t, key, oldValue)
    if not self.effects[t] then
        return
    end

    if not self.effects[t][key] then
        return
    end

    for _, effect in ipairs(self.effects[t][key]) do
        effect(oldValue)
    end
end

-- reactive函数
reactive = function(target, shallow)
    if shallow then
        return Proxy.new(target)
    end

    for k, v in pairs(target) do
        if type(v) == "table" then
            target[k] = reactive(v)
        end
    end

    if not isReactive(target) then
        target = Proxy.new(target)
    end

    return target
end

-- ref函数
ref = function(value)
    return reactive({ value = value })
end

-- 监视响应式数据变化
watch = function(effect)
    effectFuncPtr = effect
    effect()
    effectFuncPtr = nil
end

-- 取消监视
unwatch = function(t, key, effect)
    ReactiveSystem:unsubscribe(t, key, effect)
end

-- 计算属性
computed = function(options)
    local getter = nil
    local setter = nil

    if type(options) == "function" then
        getter = options
    else
        getter = options.get
        setter = options.set
    end

    local computedTable = Computed.new(getter, setter)
    return computedTable
end

-- 清理计算属性
clearComputed = function(computedTable)
    -- 清理依赖关系
    for k, v in pairs(ReactiveSystem.deps) do
        for key, computedTables in pairs(v) do
            -- 逆序遍历，防止删除元素后索引错乱
            for i = #computedTables, 1, -1 do
                if computedTables[i] == computedTable then
                    table.remove(computedTables, i)
                end
            end

            if #computedTables == 0 then
                v[key] = nil
            end
        end

        if next(v) == nil or k == computedTable then
            ReactiveSystem.deps[k] = nil
        end
    end

    -- 清理计算属性的缓存
    ReactiveSystem.caches[computedTable] = nil
end

-- 监视ref的变化
watchRef = function(refData, callback)
    watch(function(oldValue)
        callback(refData.value, oldValue)
    end)
end

-- 监视计算属性的变化
watchComputed = function(getter, callback)
    local computedValue = nil
    local oldValue = nil

    if type(getter) == "function" then
        computedValue = computed(getter)
    elseif isComputed(getter) then
        computedValue = getter
    else
        return
    end

    watch(function()
        local newValue = computedValue.value
        callback(newValue, oldValue)
        oldValue = newValue
    end)

    return computedValue
end

-- 监视Reactive对象的变化
watchReactive = function(reactiveObj, callback)
    -- 存储局部计算属性
    local computedValues = {}

    local watchReactiveImpl = nil
    watchReactiveImpl = function (obj)
        for k, v in pairs(obj._real) do
            local computedValue = computed(function()
                return obj[k]
            end)

            -- 存储局部计算属性到列表中
            table.insert(computedValues, computedValue)

            ReactiveSystem:subscribe(obj, k, function(oldValue)
                callback(computedValue.value, oldValue)
            end)

            if isReactive(v) then
                watchReactiveImpl(v, callback)
            end
        end
    end

    watchReactiveImpl(reactiveObj)

    -- 返回一个清理函数, 当不需要监视时，调用清理函数即可
    return function ()
        for _, computedValue in ipairs(computedValues) do
            clearComputed(computedValue)
        end
    end
end

return {
    ref = ref,
    reactive = reactive,

    computed = computed,
    clearComputed = clearComputed,

    watch = watch,
    unwatch = unwatch,
    
    watchRef = watchRef,
    watchComputed = watchComputed,
    watchReactive = watchReactive,

    isReactive = isReactive,
    isRef = isRef,
    isComputed = isComputed
}