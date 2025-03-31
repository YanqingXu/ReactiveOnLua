----------------------------------------------------
---模仿Vue3.0的响应式系统
---注意事项：使用watch系列函数时，回调函数尽量简单，避免在回调逻辑里继续调用watch
----------------------------------------------------
--[[ 
响应式系统
    1. 响应式对象：proxyTable，实质为Proxy代理，劫持get和set操作
    2. 计算属性：computedTable，实质为Computed代理，劫持get和set操作
    3. 副作用函数：effect，和proxyTable绑定，当proxyTable的属性发生变化时，通知effect重新执行
    4. 依赖收集：副作用函数依赖响应式对象，计算属性依赖响应式对象, 计算属性依赖计算属性
    5. 计算属性懒计算：访问计算属性时，如果有缓存则直接返回，否则调用getter重新计算
                      当计算属性依赖的响应式对象发生变化时，清除缓存
--]]
local Stack = require("xf.engine.Stack")
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

local watch = nil           -- 监视响应式数据变化
local unwatch = nil         -- 取消监视

local watchRef = nil        -- 监视Ref对象的变化
local watchComputed = nil   -- 监视计算属性的变化
local watchReactive = nil   -- 监视Reactive对象的变化

-- 副作用函数指针栈，用于绑定与之关联的响应式对象
local effectFuncPtrStack = Stack.new()

-- 计算属性栈，用于临时存储计算属性对象
local computedTableStack = Stack.new()

-- 代理类
local Proxy = {}
Proxy.__index = function(proxyTable, key)
    if key == "_real" then
        return rawget(proxyTable, key)
    end

    -- 建立依赖关系：effect依赖proxyTable
    ReactiveSystem:subscribe(proxyTable, key, effectFuncPtrStack:top())

    -- 建立依赖关系：computedTable依赖proxyTable
    ReactiveSystem:link(proxyTable, key, computedTableStack:top())

    -- 返回访问的原始表的值
    return proxyTable._real[key]
end
Proxy.__newindex = function(proxyTable, key, newValue)
    local oldValue = proxyTable._real[key]
    if not oldValue then
        ReactiveSystem:subscribe(proxyTable, key, effectFuncPtrStack:top())
        ReactiveSystem:link(proxyTable, key, computedTableStack:top())
    end

    -- 当数据发生变化时
    if oldValue ~= newValue then
        proxyTable._real[key] = newValue
        ReactiveSystem:propgate(proxyTable, key)            -- 传播依赖关系
        ReactiveSystem:notify(proxyTable, key, oldValue)    -- 通知effect重新执行
    end
end

-- 创建代理对象
function Proxy.new(realTable)
    local proxyTable = {}
    proxyTable._real = realTable or {}
    setmetatable(proxyTable, Proxy)
    return proxyTable
end

-- 计算属性类
local Computed = {}
Computed.__index = function(computedTable, key)
    if key == "_real" then
        return rawget(computedTable, key)
    end

    -- 计算属性只有一个key，固定为"value"
    if "value" ~= key then
        return nil
    end

    -- 建立依赖关系：effect依赖computedTable
    ReactiveSystem:subscribe(computedTable, key, effectFuncPtrStack:top())

    -- 建立依赖关系：computedTable依赖computedTable
    ReactiveSystem:link(computedTable, key, computedTableStack:top())

    -- 调用getter函数之前，先将计算属性对象压入栈中，以便在getter中建立依赖关系
    computedTableStack:push(computedTable)

    -- 计算属性懒计算
    if computedTable._real._recompute then
        -- 调用getter函数
        local oldValue = computedTable._real._cachedValue
        local newValue = computedTable._real.getter(oldValue)
        computedTable._real._cachedValue = newValue

        -- 标记不需要重新计算
        computedTable._real._recompute = false
    end

    -- 弹出栈顶元素
    computedTableStack:pop()

    -- 返回计算属性的值
    return computedTable._real._cachedValue
end

Computed.__newindex = function(computedTable, key, newValue)
    -- 计算属性只有一个key，固定为"value"
    if "value" ~= key then
        return
    end

    -- 更新计算属性的值
    local oldValue = computedTable._real._cachedValue
    computedTable._real._cachedValue = newValue

    -- 如果计算数值有setter函数，则调用setter函数
    if computedTable._real.setter then
        computedTable._real.setter(newValue)
    end

    -- 通知与之绑定的副作用函数重新执行
    if oldValue ~= newValue then
        ReactiveSystem:propgate(computedTable, key)
        ReactiveSystem:notify(computedTable, key, oldValue)
    end
end

-- 创建计算属性对象
function Computed.new(getter, setter)
    local realTable = {}
    realTable.getter = getter
    realTable.setter = setter

    -- 缓存计算属性的值
    realTable._cachedValue = nil
    realTable._recompute = true

    local computedTable = {}
    computedTable._real = realTable

    setmetatable(computedTable, Computed)
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

-- 建立依赖关系：t可能是proxyTable，也可能是computedTable
function ReactiveSystem:link(t, key, target)
    if not target then
        return
    end

    if not self.deps[t] then
        self.deps[t] = {}
    end

    if not self.deps[t][key] then
        self.deps[t][key] = {}
    end

    for _, v in ipairs(self.deps[t][key]) do
        if v == target then
            return
        end
    end

    table.insert(self.deps[t][key], target)
end

-- 遍历依赖关系表，清理目标计算属性的依赖关系
function ReactiveSystem:clearLink(computedTable)
    for k, v in pairs(self.deps) do
        for key, computedTables in pairs(v) do
            for i = #computedTables, 1, -1 do
                if computedTables[i] == computedTable then
                    table.remove(computedTables, i) -- 逆序遍历，防止删除元素后索引错乱
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
end

-- 传播依赖关系：t可能是proxyTable，也可能是computedTable
function ReactiveSystem:propgate(t, key)
    if not self.deps[t] then
        return
    end

    if not self.deps[t][key] then
        return
    end

    for _, reactiveObj in ipairs(self.deps[t][key]) do
        -- 递归触发依赖关系
        if isComputed(reactiveObj) then
            reactiveObj._real._recompute = true
            self:propgate(reactiveObj, "value")
        end
    end
end

-- 订阅副作用函数
function ReactiveSystem:subscribe(t, key, effect)
    if not effect then
        return
    end

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

    -- 返回一个清理函数
    return function ()
        if isComputed(t) then
            self:clearLink(t)
        end

        -- 取消订阅
        self:unsubscribe(t, key, effect)
    end
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
            break
        end
    end

    if #self.effects[t][key] == 0 then
        self.effects[t][key] = nil
    end

    if #self.effects[t] == 0 then
        self.effects[t] = nil
    end
end

-- 清除副作用函数
local stopEffect = function(effectPtr)
    if not effectPtr then
        return
    end

    for t, effects in pairs(ReactiveSystem.effects) do
        for key, effectList in pairs(effects) do
            for i = #effectList, 1, -1 do
                if effectList[i] == effectPtr then
                    table.remove(effectList, i)
                end
            end

            if #effectList == 0 then
                effects[key] = nil
            end
        end

        if next(effects) == nil then
            ReactiveSystem.effects[t] = nil
        end
    end
end

-- 通知effect重新执行
function ReactiveSystem:notify(t, key, oldValue)
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

-- 返回一个对象的响应式代理。
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

-- 接受一个内部值，返回一个响应式的、可更改的 ref 对象，此对象只有一个指向其内部值的属性 .value。
ref = function(value)
    return reactive({ value = value })
end

-- 立即运行一个函数，同时响应式地追踪其依赖，并在依赖更改时重新执行。VUE3.0的watchEffect
watch = function(effect)
    effectFuncPtrStack:push(effect)
    effect()
    effectFuncPtrStack:pop()

    return function()
        stopEffect(effect)
    end
end

-- 取消监视
unwatch = function(t, key, effect)
    ReactiveSystem:unsubscribe(t, key, effect)
end

-- 计算属性：VUE3.0的computed
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

-- VUE3.0中的watch函数, 参数为Ref对象， 默认是懒侦听的，即仅在侦听源发生变化时才执行回调函数。
watchRef = function(refData, callback)
    return ReactiveSystem:subscribe(refData, "value", function(oldValue)
        callback(refData.value, oldValue)
    end)
end

-- VUE3.0中的watch函数, 参数为计算属性， 默认是懒侦听的，即仅在侦听源发生变化时才执行回调函数。
watchComputed = function(computedValue, callback)
    return ReactiveSystem:subscribe(computedValue, "value", function(oldValue)
        callback(computedValue.value, oldValue)
    end)
end

-- VUE3.0中的watch函数, 参数响应式对象， 默认是懒侦听的，即仅在侦听源发生变化时才执行回调函数。
watchReactive = function(reactiveObj, callback)
    local clears = {}

    local watchReactiveImpl = nil
    watchReactiveImpl = function (obj)
        for k, v in pairs(obj._real) do
            local clear = ReactiveSystem:subscribe(obj, k, function(oldValue)
                callback(k, obj._real[k], oldValue)
            end)

            table.insert(clears, clear)

            if isReactive(v) then
                watchReactiveImpl(v, callback)
            end
        end
    end

    watchReactiveImpl(reactiveObj)

    -- 返回一个清理函数, 当不需要监视时，调用清理函数即可
    return function ()
        for _, clear in ipairs(clears) do
            clear()
        end
    end
end

return {
    ref = ref,
    reactive = reactive,
    computed = computed,

    watch = watch,
    unwatch = unwatch,
    stopEffect = stopEffect,

    watchRef = watchRef,
    watchComputed = watchComputed,
    watchReactive = watchReactive,

    isReactive = isReactive,
    isRef = isRef,
    isComputed = isComputed
}
