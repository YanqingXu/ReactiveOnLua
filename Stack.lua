-- 定义栈的元表
local Stack = {}
Stack.__index = Stack

-- 构造函数，初始化一个空栈
function Stack.new()
    local instance = setmetatable({}, Stack)
    instance.data = {}
    return instance
end

-- 入栈操作
function Stack:push(value)
    table.insert(self.data, value)
end

-- 出栈操作
function Stack:pop()
    if not self:isEmpty() then
        return table.remove(self.data)
    end
end

-- 查看栈顶元素，但不移除它
function Stack:top()
    if not self:isEmpty() then
        return self.data[#self.data]
    end
end

-- 检查栈是否为空
function Stack:isEmpty()
    return #self.data == 0
end

-- 返回栈的大小
function Stack:size()
    return #self.data
end

-- has element
function Stack:hasElement(element)
    for _, v in ipairs(self.data) do
        if v == element then
            return true
        end
    end
    
    return false
end

return Stack