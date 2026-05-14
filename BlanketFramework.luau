local Blanket = {}

local State = {}
State.__index = State

function State.new(value)
	return setmetatable({
		value = value,
		listeners = {},
		_destroyed = false,
	}, State)
end

function State:get()
	return self.value
end

function State:set(newValue)
	if self._destroyed or self.value == newValue then return end
	self.value = newValue
	for _, fn in ipairs(self.listeners) do
		task.spawn(fn, newValue)
	end
end

function State:subscribe(fn)
	if self._destroyed then return function() end end
	table.insert(self.listeners, fn)
	fn(self.value)
	return function()
		for i, v in ipairs(self.listeners) do
			if v == fn then
				table.remove(self.listeners, i)
				return
			end
		end
	end
end

function State:destroy()
	self._destroyed = true
	table.clear(self.listeners)
end

function Blanket.state(initial)
	return State.new(initial)
end

local Effect = {}
Effect.__index = Effect

function Effect.new(fn, deps)
	local self = setmetatable({ _cleanups = {}, _destroyed = false }, Effect)
	local function run()
		for _, c in ipairs(self._cleanups) do pcall(c) end
		table.clear(self._cleanups)
		local cleanup = fn()
		if typeof(cleanup) == "function" then
			table.insert(self._cleanups, cleanup)
		end
	end
	for _, dep in ipairs(deps) do
		local unsub = dep:subscribe(function()
			if not self._destroyed then run() end
		end)
		table.insert(self._cleanups, unsub)
	end
	return self
end

function Effect:destroy()
	self._destroyed = true
	for _, c in ipairs(self._cleanups) do pcall(c) end
	table.clear(self._cleanups)
end

function Blanket.effect(fn, deps)
	return Effect.new(fn, deps)
end

function Blanket.compute(fn, deps)
	local result = Blanket.state(fn())
	for _, dep in ipairs(deps) do
		dep:subscribe(function()
			result:set(fn())
		end)
	end
	return result
end

function Blanket.event(name)
	return { __event = name }
end

local function isEventKey(k)
	return typeof(k) == "table" and k.__event ~= nil
end

local function applyProps(instance, props)
	for k, v in pairs(props) do
		if not isEventKey(k) then
			if typeof(v) == "table" and getmetatable(v) == State then
				instance[k] = v:get()
				v:subscribe(function(newVal)
					if instance.Parent then
						instance[k] = newVal
					end
				end)
			else
				instance[k] = v
			end
		end
	end
	for k, v in pairs(props) do
		if isEventKey(k) then
			instance[k.__event]:Connect(v)
		end
	end
end

function Blanket.element(className, props, children)
	local instance = Instance.new(className)
	props = props or {}
	applyProps(instance, props)
	if children then
		for _, child in ipairs(children) do
			if child then
				child.Parent = instance
			end
		end
	end
	return instance
end

function Blanket.h(className, props, children)
	return Blanket.element(className, props, children)
end

function Blanket.bind(state, callback)
	return state:subscribe(callback)
end

function Blanket.ref()
	return { current = nil }
end

function Blanket.memo(fn, deps)
	local cache = { value = nil, depValues = {} }
	local function changed()
		for i, dep in ipairs(deps) do
			if dep:get() ~= cache.depValues[i] then return true end
		end
		return false
	end
	local function update()
		cache.value = fn()
		for i, dep in ipairs(deps) do
			cache.depValues[i] = dep:get()
		end
	end
	update()
	local result = Blanket.state(cache.value)
	for _, dep in ipairs(deps) do
		dep:subscribe(function()
			if changed() then
				update()
				result:set(cache.value)
			end
		end)
	end
	return result
end

function Blanket.list(stateList, renderFn, parent)
	local instances = {}
	stateList:subscribe(function(newList)
		for _, inst in ipairs(instances) do
			inst:Destroy()
		end
		table.clear(instances)
		for i, item in ipairs(newList) do
			local inst = renderFn(item, i)
			if inst then
				inst.Parent = parent
				table.insert(instances, inst)
			end
		end
	end)
	return instances
end

function Blanket.component(fn)
	return function(props)
		return fn(props or {})
	end
end

function Blanket.render(root, parent)
	root.Parent = parent
	return root
end

local Context = {}
Context.__index = Context

function Context.new(defaultValue)
	return setmetatable({ _value = defaultValue, _subscribers = {} }, Context)
end

function Context:provide(value)
	self._value = value
	for _, fn in ipairs(self._subscribers) do
		fn(value)
	end
end

function Context:consume()
	return self._value
end

function Context:subscribe(fn)
	table.insert(self._subscribers, fn)
	fn(self._value)
	return function()
		for i, v in ipairs(self._subscribers) do
			if v == fn then table.remove(self._subscribers, i) return end
		end
	end
end

function Blanket.createContext(defaultValue)
	return Context.new(defaultValue)
end

function Blanket.portal(instance, parent)
	instance.Parent = parent
	return instance
end

return Blanket
