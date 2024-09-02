local ReactiveSystem = require("ReactiveSystem")

local ref = ReactiveSystem.ref
local reactive = ReactiveSystem.reactive

local computed = ReactiveSystem.computed
local clearComputed = ReactiveSystem.clearComputed

local watch = ReactiveSystem.watch
local unwatch = ReactiveSystem.unwatch

local watchRef = ReactiveSystem.watchRef
local watchComputed = ReactiveSystem.watchComputed
local watchReactive = ReactiveSystem.watchReactive

local isReactive = ReactiveSystem.isReactive
local isComputed = ReactiveSystem.isComputed
local isReadonly = ReactiveSystem.isReadonly

local describe = {
    it = function(name, fn)
        print(name)
        fn()
    end,

    test = function(name, fn)
        print(name)
        fn()
    end
}

local callTimes = 0
local expect = function(actual)
    return {
        toBe = function(value)
            if actual == value then
                return
            end

            if type(actual) == "table" then
                for k, v in pairs(actual._real) do
                    assert(v == value[k])
                end
                return
            end

            assert(actual == value)
        end,

        toMatchObject = function(value)
            for i, v in ipairs(value) do
                assert(actual[i] == v)
            end
        end, 

        never = {
            toHaveBeenCalled = function()
                assert(callTimes == 0)
            end
        },

        toHaveBeenCalledTimes = function(value)
            assert(callTimes == value)
        end
    }
end

------------- TEST COMPUTED -------------
describe.it("should return updated value", function()
    local value = reactive({ foo = nil })
    local cValue = computed(function()
        return value.foo
    end)

    expect(cValue.value).toBe(nil)

    value.foo = 1
    expect(cValue.value).toBe(1)
end)

describe.it("should compute lazily", function()
    local value = reactive({ foo = nil })
    local getter = function()
        callTimes = callTimes + 1
        return value.foo
    end
    local cValue = computed(getter)

    -- lazy
    expect(getter).never.toHaveBeenCalled()

    expect(cValue.value).toBe(nil)
    expect(getter).toHaveBeenCalledTimes(1)

    -- should not compute again
    print(cValue.value)
    expect(getter).toHaveBeenCalledTimes(1)

    -- should not compute until needed
    value.foo = 1
    expect(getter).toHaveBeenCalledTimes(1)

    -- now it should compute
    expect(cValue.value).toBe(1)
    expect(getter).toHaveBeenCalledTimes(2)

    -- should not compute again
    print(cValue.value)
    expect(getter).toHaveBeenCalledTimes(2)
end)

describe.it('should trigger effect', function()
    local value = reactive({ foo = nil})
    local cValue = computed(function()
        return value.foo
    end)

    local dummy
    watch(function()
        dummy = cValue.value
    end)

    expect(dummy).toBe(nil)
    value.foo = 1
    expect(dummy).toBe(1)
end)

describe.it('should work when chained', function()
    local value = reactive({ foo = 0 })
    local c1 = computed(function() return value.foo end)
    local c2 = computed(function() return c1.value + 1 end)
    local c3 = computed(function() return c2.value + c1.value end)

    expect(c2.value).toBe(1)
    expect(c1.value).toBe(0)
    expect(c3.value).toBe(1)
    
    value.foo = value.foo + 1
    expect(c3.value).toBe(3)
    expect(c2.value).toBe(2)
    expect(c1.value).toBe(1)
end)

describe.it('should trigger effect when chained', function()
    local value = reactive({ foo = 0 })

    callTimes = 0
    local getter1 = function() 
        --callTimes = callTimes + 1
        return value.foo 
    end
    local c1 = computed(getter1)

    local getter2 = function() 
        callTimes = callTimes + 1
        return c1.value + 1 
    end
    local c2 = computed(getter2)

    local dummy
    watch(function()
        dummy = c2.value
    end)

    expect(dummy).toBe(1)
    --expect(getter1).toHaveBeenCalledTimes(1)
    expect(getter2).toHaveBeenCalledTimes(1)

    value.foo = value.foo + 1
    expect(dummy).toBe(2)

    -- should not result in duplicate calls
    --expect(getter1).toHaveBeenCalledTimes(2)
    expect(getter2).toHaveBeenCalledTimes(2)
end)

describe.it('should trigger effect when chained (mixed invocations)', function()
    local value = reactive({ foo = 0 })
    callTimes = 0

    local getter1 = function() 
        callTimes = callTimes + 1
        return value.foo 
    end
    local c1 = computed(getter1)

    local getter2 = function() 
        --callTimes = callTimes + 1
        return c1.value + 1 
    end
    local c2 = computed(getter2)

    local dummy
    local exeCount = 0
    watch(function()
        exeCount = exeCount + 1
        local c1Value = c1.value
        local c2Value = c2.value
        dummy = c1Value + c2Value
    end)

    expect(dummy).toBe(1)

    expect(getter1).toHaveBeenCalledTimes(1)
    --expect(getter2).toHaveBeenCalledTimes(1)

    value.foo = value.foo + 1
    print("exeCount", exeCount)
    expect(dummy).toBe(3)

    -- should not result in duplicate calls
    expect(getter1).toHaveBeenCalledTimes(2)
    --expect(getter2).toHaveBeenCalledTimes(2)
end)

describe.it('should support setter', function()
    local n = ref(1)
    local plusOne = computed({
        get = function() return n.value + 1 end,
        set = function(val) n.value = val - 1 end
    })

    expect(plusOne.value).toBe(2)
    n.value = n.value + 1     
    expect(plusOne.value).toBe(3)

    plusOne.value = 0
    expect(n.value).toBe(-1)
end)

describe.it('should trigger effect w/ setter', function()
    local n = ref(1)
    local plusOne = computed({
        get = function() return n.value + 1 end,
        set = function(val) n.value = val - 1 end
    })

    local dummy
    watch(function()
        dummy = n.value
    end)
    expect(dummy).toBe(1)

    plusOne.value = 0
    expect(dummy).toBe(-1)
end)

describe.it('should invalidate before non-computed effects', function()
    local plusOneValues = {}
    local n = ref(0)
    local plusOne = computed(function() return n.value + 1 end)
    watch(function()
        table.insert(plusOneValues, plusOne.value)
    end)
    -- access plusOne, causing it to be non-dirty
    print(plusOne.value)
    -- mutate n
    n.value = n.value + 1
    -- on the 2nd run, plusOne.value should have already updated.
    expect(plusOneValues).toMatchObject({1, 2})
end)

describe.it('should be readonly', function()
    local n = ref(1)
    local plusOne = computed(function() return n.value + 1 end)

    --expect(function() plusOne.value = 1 end).toThrow()
end)

describe.it('should be readonly', function()
    local a = reactive({ a = 1 })
    local x = computed(function() return a end)
    --expect(isReadonly(x)).toBe(true)
    --expect(isReadonly(x.value)).toBe(false)
    --expect(isReadonly(x.value.a)).toBe(false)
    local z = computed({
        get = function() return a end,
        set = function(v) a = v end
    })
    --expect(isReadonly(z)).toBe(false)
    --expect(isReadonly(z.value.a)).toBe(false)
end)


------------- TEST REACTIVE -------------
-- TODO