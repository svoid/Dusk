local function average(t)
	local sum = 0
	for i = 1, #t do
		sum += t[i]
	end
	return sum / #t
end

local function median(...)
	local copy = {...}
	local len = #copy
	table.sort(copy)
	if len % 2 == 0 then
		return (copy[len / 2] + copy[len / 2 + 1]) / 2
	end
	return copy[math.ceil(len / 2)]
end


local BenchmarkTest = {} do
	
	function BenchmarkTest.new(name, testFunction)
		local self = setmetatable({}, BenchmarkTest)
		
		self.Name = name
		self.TestFunction = testFunction
		self.Records = {}
		
		return self
	end
	
	function BenchmarkTest:Run()
		self.TestFunction()
	end
	
	function BenchmarkTest:AddRecord(time)
		table.insert(self.Records, time)
	end
	
	function BenchmarkTest:GetRecords()
		return self.Records
	end
	
	buildFinalClass("BenchmarkTest", BenchmarkTest, DuskObject)
end

local Benchmark = {} do
	
	function Benchmark.new(takes, times, name, outputFunction)
		takes = takes or 100
		assert(takes < 8000, "'takes' may not exceed limit of LUAI_MAXCSTACK (8000 elements)")
		
		local self = setmetatable({}, Benchmark)
		
		self.Completed = false
		self.Takes = takes
		self.Times = times or 100
		self.Name = name or "unnamed"
		self.OutputFunction = outputFunction or print
		
		self.Tests = {}
		self._Records = {}
		
		return self
	end
	
	function Benchmark:AddTest(name, testFunction)
		assertf(not self.Completed, "Becnhmark '%s' already completed", self.Name)
		local test = BenchmarkTest.new(name, testFunction)
		table.insert(self.Tests, test)
	end
	
	local osclock = os.clock
	local ipairs = ipairs
	
	function Benchmark:Run()
		local tests = self.Tests
		local times = self.Times
		
		for take = 1, self.Takes do
			
			for _, test in ipairs(self.Tests) do
				local START = osclock()
				
				for time = 1, times do
					test:Run()
				end
				
				local END = osclock()
				
				test:AddRecord(END - START)
			end
			
		end
		
		local maxNameSize = 0
		
		for _, test in ipairs(self.Tests) do
			local size = #test.Name
			if size > maxNameSize then
				maxNameSize = size
			end
		end
		
		maxNameSize += 1
		
		local topbarFormatString = "%-" .. maxNameSize .. "s  %-11s %-11s %-11s %-11s\n"
		local recordFormatString = "%-" .. maxNameSize .. "s: %.9f %.9f %.9f %.9f\n"
		
		local line = string.rep("=", maxNameSize + 49)
		local topbar = string.format(topbarFormatString, "name", "average", "median", "min", "max")
		local recordsOutput = ""
		
		for _, test in ipairs(self.Tests) do
			local records = test:GetRecords()
			
			recordsOutput ..= string.format(recordFormatString,
				test.Name,
				average(records),
				median(unpack(records)),
				math.min(unpack(records)),
				math.max(unpack(records))
			)
		end
		
		local output = string.format("%s\n%s\n%s%s", self.Name, line, topbar, recordsOutput)
		
		self.OutputFunction(output)
	end
	
	buildFinalClass("Benchmark", Benchmark, DuskObject)
end

local library = {}

library.average = average
library.median = median
library.Benchmark = Benchmark

return protectLib(library)