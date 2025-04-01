local ReactiveSystem = require("ReactiveSystem")


local ref = ReactiveSystem.ref
local reactive = ReactiveSystem.reactive
local computed = ReactiveSystem.computed

local watch = ReactiveSystem.watch
local unwatch = ReactiveSystem.unwatch

local watchRef = ReactiveSystem.watchRef
local watchComputed = ReactiveSystem.watchComputed
local watchReactive = ReactiveSystem.watchReactive

local isReactive = ReactiveSystem.isReactive
local isComputed = ReactiveSystem.isComputed
local isRef = ReactiveSystem.isRef

local describe = function(desc, fn)
    print(desc)
    fn()
end

local it = function(desc, fn)
    print(desc)
    fn()
end

local test = function(desc, fn)
    print(desc)
    fn()
end

local visit = function(value)
    -- do nothing
end

local expect = function(actual)
    return {
        toBe = function(value)
            assert(actual == value)
        end
    }
end

--------------- TEST REF ---------------
describe('reactivity/ref', function()
    it('should hold a value', function()
        local a = ref(1)
        expect(a.value).toBe(1)
        a.value = 2
        expect(a.value).toBe(2)
    end)

    it('should be reactive', function()
        local a = ref(1)
        local dummy
        local calledTimes = 0
        watch(function()
            calledTimes = calledTimes + 1
            dummy = a.value
        end)

        expect(calledTimes).toBe(1)
        expect(dummy).toBe(1)
        a.value = 2
        expect(calledTimes).toBe(2)
        expect(dummy).toBe(2)
        a.value = 2
        expect(calledTimes).toBe(2)
    end)

    it('should make nested properties reactive', function()
        local a = ref({
            count = 1
        })
        local dummy
        watch(function()
            dummy = a.value.count
        end)

        expect(dummy).toBe(1)
        a.value.count = 2
        expect(dummy).toBe(2)
    end)

    it('should work without initial value', function()
        local a = ref()
        local dummy
        watch(function()
            dummy = a.value
        end)

        expect(dummy).toBe(nil)
        a.value = 2
        expect(dummy).toBe(2)
    end)

    it('should work like a normal property when nested in a reactive object', function()
        local a = ref(1)
        local obj = reactive({
            a = a,
            b = {
                c = a
            }
        })

        local dummy1
        local dummy2

        watch(function()
            dummy1 = obj.a.value
            dummy2 = obj.b.c.value
        end)

        local assertDummiesEqualTo = function(val)
            expect(dummy1).toBe(val)
            expect(dummy2).toBe(val)
        end

        assertDummiesEqualTo(1)
        a.value = a.value + 1
        assertDummiesEqualTo(2)
        obj.a.value = obj.a.value + 1
        assertDummiesEqualTo(3)
        obj.b.c.value = obj.b.c.value + 1
        assertDummiesEqualTo(4)
    end)

    -- it('should unwrap nested ref in types', function()
    --     local a = ref(0)
    --     local b = ref(a)

    --     expect(type(b.value + 1)).toBe('number')
    -- end)

    -- skip array test
end)

-- test('unref', function()
--     expect(unref(1)).toBe(1)
--     expect(unref(ref(1))).toBe(1)
-- end)

-- test('shallowRef', function()
--     local sref = shallowRef({ a = 1 })
--     expect(isReactive(sref.value)).toBe(false)

--     local dummy
--     watch(function()
--         dummy = sref.value.a
--     end)

--     expect(dummy).toBe(1)
--     sref.value = { a = 2 }

--     expect(isReactive(sref.value)).toBe(false)
--     expect(dummy).toBe(2)
-- end)

-- test('shallowRef force trigger', function()
--     local sref = shallowRef({ a = 1 })
--     local dummy
--     watch(function()
--         dummy = sref.value.a
--     end)

--     expect(dummy).toBe(1)
--     sref.value.a = 2
--     expect(dummy).toBe(1) -- should not trigger yet

--     -- force trigger
--     triggerRef(sref)
--     expect(dummy).toBe(2)
-- end)

-- test('shallowRef is shallow', function()
--     expect(isShallow(shallowRef({ a = 1 }))).toBe(true)
-- end)

-- test('isRef', function()
--     expect(isRef(ref(1))).toBe(true)
--     expect(isRef(computed(function() return 1 end))).toBe(true)

--     expect(isRef(0)).toBe(false)
--     expect(isRef(1)).toBe(false)

--     --an object that looks like a ref isn't necessarily a ref
--     expect(isRef({ value = 0 })).toBe(false)
-- end)

-- test('toRef', function()
--     local a = reactive({ x = 1 })
--     local x = toRef(a, 'x')

--     local b = ref({y = 1})
--     local c = toRef(b)
--     local d = toRef({ z = 1 })

--     expect(isRef(d)).toBe(true)
--     expect(d.value.z).toBe(1)
--     expect(c).toBe(b)

--     expect(isRef(x)).toBe(true)
--     expect(x.value).toBe(1)

--     -- source -> proxy
--     a.x = 2
--     expect(x.value).toBe(2)

--     -- proxy -> source
--     x.value = 3
--     expect(a.x).toBe(3)

--     -- reactivity
--     local dummyX
--     watch(function()
--         dummyX = x.value
--     end)
--     expect(dummyX).toBe(x.value)

--     -- mutating source should trigger effect using the proxy refs
--     a.x = 4
--     expect(dummyX).toBe(4)

--     -- should keep ref
--     local r = { x = ref(1) }
--     expect(toRef(r, 'x')).toBe(r.x)
-- end)

-- test('toRef default value', function()
--     local a = { x = nil}
--     local x = toRef(a, 'x', 1)
--     expect(x.value).toBe(1)

--     a.x = 2
--     expect(x.value).toBe(2)

--     a.x = nil
--     expect(x.value).toBe(1)
-- end)

------------- TEST COMPUTED -------------

describe('reactivity/computed', function()
    it('should return updated value', function()
        local value = reactive({ foo = nil })
        local cValue = computed(function()
            return value.foo
        end)
        expect(cValue.value).toBe(nil)
        value.foo = 1
        expect(cValue.value).toBe(1)
    end)

    it('pass oldValue to computed getter', function()
        local count = ref(0)
        local oldValue = ref()
        local curValue = computed(function(pre)
            oldValue.value = pre
            return count.value
        end)

        expect(curValue.value).toBe(0)
        expect(oldValue.value).toBe(nil)

        count.value = count.value + 1
        expect(curValue.value).toBe(1)
        expect(oldValue.value).toBe(0)
    end)

    it('should compute lazily', function()
        local value = reactive({ foo = nil })
        local callCnt = 0

        local getter = function()
            callCnt = callCnt + 1
            return value.foo
        end
        local cValue = computed(getter)

        -- lazy
        expect(callCnt).toBe(0)

        expect(cValue.value).toBe(nil)
        expect(callCnt).toBe(1)

        -- should not compute again
        visit(cValue.value)
        expect(callCnt).toBe(1)

        -- should not compute until needed
        value.foo = 1
        expect(callCnt).toBe(1)

        -- now it should compute
        expect(cValue.value).toBe(1)
        expect(callCnt).toBe(2)

        -- should not compute again
        visit(cValue.value)
        expect(callCnt).toBe(2)
    end)

    it('should trigger effect', function()
        local value = reactive({ foo = nil })
        local cvalue = computed(function()
            return value.foo
        end)

        local dummy
        watch(function()
            dummy = cvalue.value
        end)

        expect(dummy).toBe(nil)
        value.foo = 1
        expect(dummy).toBe(1)
    end)

    it('should work when chained', function()
        local value = reactive({ foo = 0 })
        local c1 = computed(function()
            return value.foo
        end)
        local c2 = computed(function()
            return c1.value + 1
        end)

        expect(c2.value).toBe(1)
        expect(c1.value).toBe(0)

        value.foo = value.foo + 1

        expect(c2.value).toBe(2)
        expect(c1.value).toBe(1)
    end)

    it('should trigger effect when chained', function()
        local value = reactive({ foo = 0 })
        local getter1_callCnt = 0
        local getter2_callCnt = 0

        local getter1 = function()
            getter1_callCnt = getter1_callCnt + 1
            return value.foo
        end

        local c1 = computed(getter1)
        local getter2 = function()
            getter2_callCnt = getter2_callCnt + 1
            return c1.value + 1
        end
        local c2 = computed(getter2)

        local dummy
        watch(function()
            dummy = c2.value
        end)

        expect(dummy).toBe(1)
        expect(getter1_callCnt).toBe(1)
        expect(getter2_callCnt).toBe(1)

        value.foo = value.foo + 1
        expect(dummy).toBe(2)

        -- should not result in duplicate calls
        expect(getter1_callCnt).toBe(2)
        expect(getter2_callCnt).toBe(2)
    end)

    it('should trigger effect when chained (mixed invocations)', function()
        local value = reactive({ foo = 0 })
        local getter1_callCnt = 0
        local getter2_callCnt = 0

        local getter1 = function()
            getter1_callCnt = getter1_callCnt + 1
            return value.foo
        end
        local c1 = computed(getter1)

        local getter2 = function()
            getter2_callCnt = getter2_callCnt + 1
            return c1.value + 1
        end
        local c2 = computed(getter2)

        local dummy
        watch(function()
            dummy = c1.value + c2.value
        end)

        expect(dummy).toBe(1)
        expect(getter1_callCnt).toBe(1)
        expect(getter2_callCnt).toBe(1)
        value.foo = value.foo + 1
        expect(dummy).toBe(3)
        -- should not result in duplicate calls
        expect(getter1_callCnt).toBe(2)
        expect(getter2_callCnt).toBe(2)
    end)

    it('should support setter', function()
        local n = ref(1)
        local plusOne = computed({
            get = function()
                return n.value + 1
            end,
            set = function(val)
                n.value = val - 1
            end
        })

        expect(plusOne.value).toBe(2)
        n.value = n.value + 1
        expect(plusOne.value).toBe(3)

        plusOne.value = 0
        expect(n.value).toBe(-1)
    end)

    it('should trigger effect w/ setter', function()
        local n = ref(1)
        local plusOne = computed({
            get = function()
                return n.value + 1
            end,
            set = function(val)
                n.value = val - 1
            end
        })

        local dummy
        watch(function()
            dummy = n.value
        end)

        expect(dummy).toBe(1)
        plusOne.value = 0
        expect(dummy).toBe(-1)
    end)
end)
