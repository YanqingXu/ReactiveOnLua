# ReactiveSystem

## 概述
ReactiveSystem 是一个基于 Lua 实现的响应式系统，模仿了 Vue 3.0 的响应式机制。它提供了一套完整的 API，允许在游戏开发中使用类似 Vue 的响应式编程模式，实现数据与界面的自动同步更新。

## 核心特性
- **响应式对象**：通过 `reactive()` 函数将普通 Lua table 转换为响应式对象
- **引用对象**：通过 `ref()` 函数创建响应式引用
- **计算属性**：通过 `computed()` 函数创建基于响应式数据的计算属性
- **侦听器**：提供多种 watch 函数来监听响应式数据的变化并触发回调

## 主要概念

### 响应式对象 (Reactive Objects)
响应式对象是通过代理（Proxy）实现的，可以侦测对象属性的访问和修改操作。当响应式对象的属性被修改时，系统会自动通知所有依赖这个属性的副作用函数重新执行。

### 计算属性 (Computed Properties)
计算属性是基于响应式数据派生的值。它们具有缓存特性，只有当依赖的响应式数据发生变化时才会重新计算。

### 侦听器 (Watchers)
侦听器用于监视响应式数据的变化，并在变化发生时执行回调函数。系统提供了几种类型的侦听器：
- `watch`：通用侦听器
- `watchRef`：专门用于侦听 ref 对象
- `watchComputed`：专门用于侦听计算属性
- `watchReactive`：用于侦听响应式对象

## API 参考

### 创建响应式数据
```lua
-- 创建响应式对象
local state = reactive({ count = 0 })

-- 创建引用
local count = ref(0)

-- 创建计算属性
local doubleCount = computed(function()
    return count.value * 2
end)

-- 创建可读写的计算属性
local plusOne = computed({
    get = function()
        return count.value + 1
    end,
    set = function(val)
        count.value = val - 1
    end
})
```

### 侦听数据变化
```lua
-- 侦听 ref 对象
local stopWatch = watchRef(count, function(newValue, oldValue)
    print("Count changed:", oldValue, "->", newValue)
end)

-- 侦听计算属性
watchComputed(doubleCount, function(newValue, oldValue)
    print("Double count changed:", oldValue, "->", newValue)
end)

-- 侦听响应式对象
local stopWatchReactive = watchReactive(state, function(key, newValue, oldValue)
    print("Property", key, "changed:", oldValue, "->", newValue)
end)

-- 停止侦听
stopWatch()
stopWatchReactive()
```

### 工具函数
```lua
-- 检查对象是否为响应式对象
if isReactive(obj) then
    -- ...
end

-- 检查对象是否为 ref
if isRef(obj) then
    -- ...
end

-- 检查对象是否为计算属性
if isComputed(obj) then
    -- ...
end
```

## 使用注意事项
1. 使用 watch 系列函数时，回调函数应尽量简单，避免在回调逻辑中继续调用 watch
2. 计算属性依赖的数据必须是响应式的，否则无法正确触发重新计算
3. 在多层嵌套的对象中，默认情况下所有层级都会被转换为响应式
4. 为了避免循环依赖，不建议在一个计算属性的 getter 中访问另一个依赖第一个计算属性的计算属性

## 实现原理
ReactiveSystem 基于以下几个核心机制：

1. **代理对象**：使用 Lua 的元表（metatable）机制实现对象的代理，劫持 get 和 set 操作
2. **依赖收集**：在访问响应式对象属性时，收集当前正在执行的副作用函数
3. **变更通知**：当响应式对象的属性被修改时，通知所有依赖这个属性的副作用函数重新执行
4. **计算属性缓存**：计算属性使用缓存机制，避免重复计算，只有在依赖的响应式数据变化时才会重新计算

## 示例

### 基本用法示例
```lua
local ReactiveSystem = require("xf.engine.ReactiveSystem")
local ref = ReactiveSystem.ref
local reactive = ReactiveSystem.reactive
local computed = ReactiveSystem.computed
local watchRef = ReactiveSystem.watchRef

-- 创建响应式数据
local count = ref(0)
local doubleCount = computed(function()
    return count.value * 2
end)

-- 监听变化
watchRef(count, function(newValue, oldValue)
    print("Count changed from", oldValue, "to", newValue)
    print("Double count is now", doubleCount.value)
end)

-- 修改数据，会触发监听器
count.value = 1  -- 输出: Count changed from 0 to 1, Double count is now 2
count.value = 2  -- 输出: Count changed from 1 to 2, Double count is now 4
```

### UI绑定示例
```lua
local ReactiveSystem = require("xf.engine.ReactiveSystem")
local ref = ReactiveSystem.ref
local watchRef = ReactiveSystem.watchRef

-- 创建UI状态
local uiState = ref({
    visible = true,
    text = "Hello World",
    color = {r=255, g=255, b=255}
})

-- 监听变化并更新UI
watchRef(uiState, function()
    if uiState.value.visible then
        -- 更新UI显示
        updateUIText(uiState.value.text)
        updateUIColor(uiState.value.color)
    else
        -- 隐藏UI
        hideUI()
    end
end)

-- 在需要时更新状态
function changeUIState()
    uiState.value.text = "New Text"
    uiState.value.color.r = 200  -- 嵌套属性也是响应式的
end
```

## 背后的思想
ReactiveSystem 采用了声明式编程范式，使开发者能够将注意力集中在数据的变化上，而不是手动管理 UI 更新的过程。这种方式可以有效减少代码量，并使逻辑更加清晰。
