--!strict
-- Minimal typed signal for service-to-service events. Handlers run synchronously (until they yield), each in its own thread.

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Handler = (...any) -> ()

type SignalImpl = {
	_handlers: { [Handler]: boolean },
	Connect: (self: SignalImpl, handler: Handler) -> Connection,
	Once: (self: SignalImpl, handler: Handler) -> Connection,
	Fire: (self: SignalImpl, ...any) -> (),
	DisconnectAll: (self: SignalImpl) -> (),
}

local Signal = {}
Signal.__index = Signal

local function makeConnection(impl: SignalImpl, handler: Handler): Connection
	local conn = { Connected = true } :: any
	function conn.Disconnect(self: any)
		if self.Connected then
			self.Connected = false
			impl._handlers[handler] = nil
		end
	end
	return conn :: Connection
end

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _handlers = {} }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal.Connect(self: SignalImpl, handler: Handler): Connection
	self._handlers[handler] = true
	return makeConnection(self, handler)
end

function Signal.Once(self: SignalImpl, handler: Handler): Connection
	local conn: Connection
	conn = Signal.Connect(self, function(...)
		conn:Disconnect()
		handler(...)
	end)
	return conn
end

function Signal.Fire(self: SignalImpl, ...: any)
	for handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal.DisconnectAll(self: SignalImpl)
	table.clear(self._handlers)
end

return Signal
