-- Signal module by Drastic
-- Fastest signal module possibly

local FreeRunnerThread = nil

local function AcquireRunnerThreadAndCallEventHandler(Fn, ...)
	local AcquiredRunnerThread = FreeRunnerThread
	FreeRunnerThread = nil
	Fn(...)
	FreeRunnerThread = AcquiredRunnerThread
end

local function RunEventHandlerInFreeThread(...)
	AcquireRunnerThreadAndCallEventHandler(...)
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function Connection_Disconnect(self: Connection)
	-- do NOT use variables for Prev, Next
	-- using variables could cause crashes in live games
	
	local Signal = self.Signal
	
	if self.Prev then
		self.Prev.Next = self.Next
	end
	
	if self.Next then
		self.Next.Prev = self.Prev
	end
	
	if Signal.Connections == self then
		Signal.Connections = self.Next
	end
end

local ConnectionClass = {
	-- Have memory reserved for these values
	Fn = function()end,
	Signal = {},
	Next = false,
	Prev = false,

	Disconnect = Connection_Disconnect,
	Destroy = Connection_Disconnect,
}

local SignalClass = {
	Connections = false,
	
	Fire = function<T...>(self: Signal, ...: T...)		
		local Node = self.Connections
		if not Node then return end
		
		local function ThreadTask(...)
			while Node do
				Node.Fn(...)
				Node = Node and Node.Next
			end
		end

		while Node do
			FreeRunnerThread = FreeRunnerThread or coroutine.create(RunEventHandlerInFreeThread)
			task.spawn(FreeRunnerThread, ThreadTask, ...)
			Node = Node and Node.Next
		end
	end,
	Once = function<T...>(self: Signal, Fn: (T...) -> (T...))
		local Disconnected = false
		local Connection; Connection = self:Connect(function(...)
			if Disconnected then return end
			Disconnected = true
			Connection:Disconnect()
			Fn(...)
		end)

		return Connection
	end,
	Wait = function(self: Signal)
		local Running = coroutine.running()
		self:Once(function(...)
			if coroutine.status(Running) ~= "suspended" then return end
			task.spawn(Running, ...)
		end)
		return coroutine.yield()
	end,
	Connect = function<T...>(self: Signal, Fn: (T...) -> (T...))
		local Connection = table.clone(ConnectionClass)
		Connection.Signal = self
		Connection.Fn = Fn
		Connection.Next = self.Connections
		
		if self.Connections then
			self.Connections.Prev = Connection
		end
		
		self.Connections = Connection

		return Connection
	end,
	DisconnectAll = function(self: Signal)
		self.Connections = false
	end,
	Destroy = function(self: Signal)
		self:DisconnectAll()
		
		-- odd typechecker workaround :(
		local Proxy = self.Proxy
		if Proxy then
			Proxy:Disconnect()
		end

		table.clear(self)
	end,
}

type Signal = {
	Connections: Connection | false,
	Proxy: RBXScriptConnection?,

	Fire: typeof(SignalClass.Fire),
	Once: typeof(SignalClass.Once),
	Wait: typeof(SignalClass.Wait),
	Connect: typeof(SignalClass.Connect),
	DisconnectAll: typeof(SignalClass.DisconnectAll),
	Destroy: typeof(SignalClass.Destroy),
}

type Connection = {
	Signal: Signal,
	
	Next: Connection | any,
	Prev: Connection | any, -- any to silence type checker error -_-

	Fn: <T...>(T...) -> (T...),
	Disconnect: typeof(ConnectionClass.Disconnect),
	Destroy: typeof(ConnectionClass.Destroy),
}

return {
	new = function(): Signal
		return table.clone(SignalClass)
	end,

	Wrap = function(RBXScriptSignal: RBXScriptSignal): Signal
		local NewSignal = table.clone(SignalClass)

		NewSignal.Proxy = RBXScriptSignal:Connect(function(...)
			NewSignal:Fire(...)
		end)

		return NewSignal
	end,
}
