#!/usr/bin/env lua
-- <!-- vim : set ts=4 sts=4 et : -->
-- <img src=tree.png align=left width=500>
local l,the={},{}; l.help=[[
# tree.lua 
Multi-objective tree generation   
(c)2024 Tim Menzies <timm@ieee.org> MIT license

## INSTALL
wget https://raw.githubusercontent.com/timm/ezr/main/src/tree.lua

## USAGE 
lua sandbox.lua [OPTIONS] [ACTIONS]

## OPTIONS
      -b --bins   number of bins (before merging) = 17
      -c --cohen  less than cohen*sd means "same" = 0.35
      -f --fmt    format string for number        = %g
      -h --help   show help                       = false
      -s --seed   random number seed              = 1234567891
      -t --train  training data                   = ../data/misc/auto93.csv
      actions     list available start up actions

## DATA FORMAT
Sample data for this code can be downloaded from
github.com/timm/ezr/tree/main/data/\*/\*.csv    
(pleae ignore the "old" directory)

This data is in a  csv format.  The names in row1 indicate which
columns are:

- numeric columns as this starting in upper case (and other columns 
  are symbolic)
- goal columns are numerics ending in "+,-" for "maximize,minize".  

After row1, the other rows are floats or integers or strings
booleans ("true,false") or "?" (for don't know). e.g

     Clndrs, Volume,  HpX,  Model, origin,  Lbs-,   Acc+,  Mpg+
     4,      90,       48,   80,   2,       2335,   23.7,   40
     4,      98,       68,   78,   3,       2135,   16.6,   30
     4,      86,       65,   80,   3,       2019,   16.4,   40
     ...     ...      ...   ...    ...      ...     ...    ...
     4,      121,      76,   72,   2,       2511,   18,     20
     8,      302,     130,   77,   1,       4295,   14.9,   20
     8,      318,     210,   70,   1,       4382,   13.5,   10

Internally, rows are sorted by the the goal columns. e.g. in the above
rows, the top rows are best (minimal Lbs, max Acc, max Mpg). The
tree generated by this code reports a how to select for rows of
different value. The left-ish branch of that tree points to the
better rows.

## IN THIS CODE...
- Function args prefixed by two spaces are optional inputs.
  In the typehints, these arguments are marked with a "?".
- Function args prefixed by four spaces are local to that function.
- UPPPER CASE words are classes; 
- Type `table`s are either of type `list` (numberic indexes) or 
  `dict` (symbolic indexes). 
- Type `num` (not to be confused with class NUM) are floats or ints. 
- Type `atom` are bools, strs, or nums.
- Type `thing` are atoms or "?" (for "don't know").
- Type `rows` are lists of things; i.e. `row  =  list[thing]`. ]]

local DATA,SYM,NUM,COLS,BIN,TREE = {},{},{},{},{},{}
local abs, max, min, rand = math.abs, math.max, math.min, math.random
l.inf=1E30
-- ---------------------------------------------------------------------------------------
-- ## Data layer
-- ### class NUM
-- Incremental update of summary of numbers.

-- `NUM.new(?name:str, ?pos:int) -> NUM`  
function NUM.new(  name,pos)
  return l.new(NUM,{name=name, pos=pos, n=0, mu=0, m2=0, sd=0, lo=l.inf, hi= -l.inf,
                  goal= (name or ""):find"-$" and 0 or 1}) end

-- `NUM:add(x:num) -> x`
function NUM:add(x,     d)
  if x ~= "?" then
    self.n  = self.n + 1
    d       = x - self.mu
    self.mu = self.mu + d/self.n
    self.m2 = self.m2 + d*(x - self.mu)
    self.sd = self.n<2 and 0 or (self.m2/(self.n - 1))^.5 
    self.lo = min(x, self.lo)
    self.hi = max(x, self.hi)
    return x end end 

-- `NUM:norm(x:num) -> 0..1`
function NUM:norm(x) return x=="?" and x or (x - self.lo)/(self.hi - self.lo) end

-- `NUM:small(x:num) -> bool`
function NUM:small(x) return x < the.cohen * self.sd end

-- `NUM:same(i:NUM, j:NUM) -> bool`   
-- True if statistically insignificantly different (using Cohen's rule).
-- Used to decide if two BINs should be merged.
function NUM.same(i,j,    pooled)
  pooled = (((i.n-1)*i.sd^2 + (j.n-1)*j.sd^2)/ (i.n+j.n-2))^0.5
  return abs(i.mu - j.mu) / pooled <= (the.cohen or .35) end

-- ### class SYM
-- Incremental update of summary of symbols.

-- `SYM.new(?name:str, ?pos:int) -> SYM`  
function SYM.new(  name,pos)
  return l.new(SYM,{name=name, pos=pos, n=0, has={}, most=0, mode=nil}) end

-- `SYM:add(x:any) -> x`
function SYM:add(x,     d)
  if x ~= "?" then
    self.n  = self.n + 1
    self.has[x] = 1 + (self.has[x] or 0)
    if self.has[x] > self.most then self.most,self.mode = self.has[x], x end 
    return x end end

-- ### class DATA
-- Manage rows, and their summaries in columns

-- `DATA.new() -> DATA`
function DATA.new() return l.new(DATA, {rows={}, cols=nil}) end

-- `DATA:read(file:str) -> DATA`   
-- Imports the rows from `file` contents into `self`.
function DATA:import(file) 
  for row in l.csv(file) do self:add(row) end; return self end

-- `DATA:load(t:list) -> DATA`   
-- Loads the rows from `t` `self`.
function DATA:load(t)    
  for _,row in pairs(t)  do self:add(row) end; return self end

-- `DATA:clone(?init:list) -> DATA`     
-- ①  Create a DATA with same column roles as `self`.   
-- ②  Loads rows (if any) from `init`.
function DATA:clone(  init) 
   return DATA:new():load({self.cols.names}) -- ①  
                    :load(init or {}) end    -- ② 

-- `DATA:add(row:list) -> nil`    
-- Create or update  the summaries in `self.cols`.
-- If not the first row, push this `row` onto `self.rows`.
function DATA:add(row)
  if self.cols then l.push(self.rows, self.cols:add(row)) else 
     self.cols = COLS.new(row) end end 

-- ### class COLS
-- Column creation and column updates.

-- `COLS.new(row: list[str]) -> COLS`
-- Upper case prefix means number (else you are a symbol). 
-- Suffix `X` means "ignore". Suffix "+,-,!" means maximize, minimize, or klass.
function COLS.new(row,    self,skip,col)
  self = l.new(COLS,{names=row, all={},x={}, y={}, klass=nil})
  skip={}
  for k,v in pairs(row) do
    col = l.push(v:find"X$" and skip or v:find"[!+-]$" and self.y or self.x,
                 l.push(self.all, 
                        (v:find"^[A-Z]" and NUM or SYM).new(v,k))) 
    if v:find"!$" then self.klass=col end end
  return self end 

-- `COLS:add(row:list[thing]) -> row`
function COLS:add(row)
  for _,cols in pairs{self.x, self.y} do
    for _,col in pairs(cols) do  col:add(row[col.pos]) end end 
  return row end
------------------------------------------------------------------------------
-- ## Inference Layer

-- `DATA:chebyshev(row:list) -> 0..1`    
-- Report distance to best solution (and _lower_ numbers are _better_).    
function DATA:chebyshev(row,     d) 
  d=0; for _,c in pairs(self.cols.y) do d = max(d,abs(c:norm(row[c.pos]) - c.goal)) end
  return d end
  
-- `DATA:sort() -> DATA`   
-- Sort rows by `chebyshev` (so best rows appear first). 
function DATA:sort()
  table.sort(self.rows, function(a,b) return self:chebyshev(a) < self:chebyshev(b) end)
  return self end 

-- ### class BIN: discretization
-- BINs hold information on what happens to some `y` variable as we move from
-- `lo` to `hi` in another column. TREEs will be built by searching through the bins.

-- `BIN.new(name:str, pos:int, ?lo:atom, ?hi:atom) -> BIN`
function BIN.new(name,pos,  lo,hi)
  hi = hi or lo or -l.inf
  lo = lo or l.inf
  return l.new(BIN,{name=name, pos=pos, lo=lo, hi= hi, y=NUM.new()}) end

-- `BIN:add(row:row, y:num) -> nil`    
-- ①  Expand `lo` and `hi` to cover `x`.     
-- ②  Update `self.y` with `y`.
function BIN:add(row,y,     x) 
  x = row[self.pos]
  if x ~= "?" then
    if x < self.lo then self.lo = x end -- ①  
    if x > self.hi then self.hi = x end -- ①  
    self.y:add(y) end end -- ②  

-- `BIN:__tostring() -> str`
function BIN:__tostring(     lo,hi,s)
  lo,hi,s = self.lo, self.hi,self.name
  if lo == -l.inf then return l.fmt("%s <= %g", s,hi) end
  if hi ==  l.inf then return l.fmt("%s > %g",s,lo) end
  if lo ==  hi  then return l.fmt("%s == %s",s,lo) end
  return l.fmt("%g < %s <= %g", lo, s, hi) end

-- `BIN:selects(rows: list[row]) : list[row]`   
-- Return the subset of `rows` selected by `self`.
function BIN:selects(rows,     u)
  u={}; for _,r in pairs(rows) do if self:select(r) then l.push(u,r) end end; return u end

-- `BIN:select(row: row) : bool`
function BIN:select(row,     x)
  x=row[self.pos]
  return (x=="?") or (self.lo==self.hi and self.lo==x) or (self.lo < x and x <= self.hi) end

-- ### Bin generation
-- `DATA:bins(?rows: list[rows]) : dict[int, list[bins]] `   
-- ①  For each x-columns,    
-- ②  Return  a list of  bins ...    
-- ③  ... that separate  the Chebyshev distances ...   
-- ④  ... rejecting any bin that span from minus to plus infinity.
function DATA:bins(  rows,      tbins) 
  tbins, rows = {}, rows or self.rows
  for _,col in pairs(self.cols.x) do -- ①
    tbins[col.pos] = {}
    for _,bin in pairs(col:bins(self:dontKnowSort(col.pos,rows), -- ②  
                               function(row) return self:chebyshev(row) end)) do -- ③  
      if not (bin.lo== -l.inf and bin.hi==l.inf) then --  ④     
         l.push(tbins[col.pos],bin) end end  end
  return tbins end 

-- `DATA:dontKnowSort(pos:int, rows: list[row]) : list[row]`    
-- Sort rows on item `pos`, pushing all the "?" values to the front of the list.   
function DATA:dontKnowSort(pos,rows,     val,down)
  val  = function(a)   return a[pos]=="?" and -l.inf or a[pos] end  
  down = function(a,b) return val(a) < val(b) end  
  return l.sort(rows or self.rows, down) end  

-- `SYM:bins(rows:list[row], y:callable) -> list[BIN]`   
-- Generate one bin for each symbol seen in a  SYM column.
function SYM:bins(rows,y,     out,x) 
  out={}
  for k,row in pairs(rows) do
    x= row[self.pos]
    if x ~= "?" then
      out[x] = out[x] or BIN.new(self.name,self.pos,x)
      out[x]:add(row,y(row)) end end
  return out end

-- `NUM:bins(rows:list[row], y:callable) -> list[BIN]`   
-- Generate one bins for the numeric ranges in this column. Assumes
-- rows are sorted with all the "?" values pushed to the front. Run
-- over rows till we clear the "?" values, then set `want` the
-- remaining rows divided by `the.bins`.  Collect `x` and `y(row)`
-- values for each remaining row, saving them in `b` (the new bin)
-- and `ab` the combination of the new bin and the last thing we
-- added to `out`.
local _newBin, _fillGaps
function NUM:bins(rows,y,     out,b,ab,want,b4,x)
  out = {} 
  b = BIN.new(self.name, self.pos) 
  ab= BIN.new(self.name, self.pos)
  for k,row in pairs(rows) do
    x = row[self.pos] 
    if x ~= "?" then 
      want = want or (#rows - k - 1)/the.bins
      if x ~= b4 and                 -- if there is a break between values
         b.y.n >= want and           -- and the current bin is big enough
         #rows - k > want and        -- and after, there is space for 1 more bin 
         not self:small(b.hi - b.lo) -- the span of this bin is not trivially small
      then 
         b,ab = _newBin(b,ab,x,out)  -- ensure the `b` info is added to end of `out`
      end
      b:add(row,y(row))    -- update the current new bin
      ab:add(row,y(row))   -- update the combination of current new bin and end of `out`
      b4 = x end 
  end
  _newBin(b,ab,x,out) -- handle end of list
  return _fillGaps(out) end 

-- helper function for NUM:bins. If the new bin is the same as the last bin,
-- then replace the last bin with `ab` (which is the new bin plus the last bin).
-- Else push the new bin onto `out`.
function _newBin(b,ab,x,out,      a)
  a = out[#out]
  if   a and a.y:same(b.y)  
  then out[#out] = ab     -- replace the last bin with last plus `b`
  else l.push(out,b) end  -- add `b` to the out
  return BIN.new(b.name,b.pos,x), l.copy(out[#out]) end -- return the new b,ab

-- helper function for NUM:bins. Fill in any gaps in the bins
function _fillGaps(out)
  out[1].lo    = -l.inf  -- expand out to cover -infinity to...
  out[#out].hi =  l.inf  -- ... plus infinity
  for k = 2,#out do out[k].lo = out[k-1].hi end  -- fill in any gaps with the bins
  return out end

-- ### Tree
function TREE.new(data,  tbins,stop,name,pos,lo,hi,mu,     self,sub) 
  self = l.new(TREE,{name=name, pos=pos, lo=lo, hi=hi, mu=mu, here=data, kids={}}) 
  tbins = tbins or data:bins(data)
  stop = stop or 4
  for _,bin in l.sort(tbins[ self:argMin(data.rows,tbins) ], l.by"mu") do
    sub = bin:selects(data.rows)
    if #sub < #data.rows and #sub > stop then
      self.kinds[bin.pos] = TREE.new(data:clone(sub), tbins, stop,
                                     bin.name, bin.pos, bin.lo, bin.hi, bin.mu) end end
  return self end 

function DATA:argMin(rows,tbins,    lo,tmp,out)
  lo = l.inf
  for pos,bins in pairs(tbins) do
    tmp = self:arg(rows,bins)
    if tmp < lo then lo,out = tmp,pos end end
  return out end

function DATA:arg(rows,bins,    w,num)
  w = 0
  for _,bin in pairs(bins) do
    num = NUM.new()
    for _,r in pairs(rows) do if bin:select(r) then num:add(self:chebyshev(r)) end end
    bin.mu = num.mu
    w = w + num.n*num.sd end
  return w/#rows end

function TREE:visitor(fun,lvl)
  lvl = lvl or 0
  fun(self,lvl)
  for _,sub in pairs(self._kids) do if sub.kids then self:visitor(lvl+1) end end end
  
------------------------------------------------------------------------------
-- ## Lib

-- ### Object creation
local _id = 0
local function id() _id = _id + 1; return _id end

-- `new(klass: klass, t: dict) -> dict`      
-- Add a unique `id`; connection `t` to its `klass`; ensure `klass` knows to call itself.
function l.new (klass,t) 
  t._id=id(); klass.__index=klass; setmetatable(t,klass); return t end

-- ### Lists
-- `push(t: list, x:any) -> x`
function l.push(t,x) t[1+#t]=x; return x end 

-- `sort(t: list, ?fun:callable) -> list`
function l.sort(t,  fun) table.sort(t,fun); return t end

function l.by(x) 
  return type(x)=="function" and function(a,b) return x(a) < x(b) end 
                             or  function(a,b) return a[x] < b[x] end end 

-- `copy(t: any) -> any`
function l.copy(t,     u)
  if type(t) ~= "table" then return t end 
  u={}; for k,v in pairs(t) do u[l.copy(k)] = l.copy(v) end 
  return setmetatable(u, getmetatable(t)) end

-- ### Thing to string
l.fmt = string.format

-- `oo(x:any) : x`   
-- Show `x`, then return it.
function l.oo(x) print(l.o(x)); return x end

-- `o(x:any) : str`   
-- Generate a show string for `x`.
function l.o(x)
  if type(x)=="number" then return l.fmt(the.fmt or "%g",x) end
  if type(x)~="table"  then return tostring(x) end 
  return "{" .. table.concat(#x==0 and l.okeys(x) or l.olist(x),", ")  .. "}" end

-- `olist(t:list) : str`   
-- Generate a show string for tables with numeric indexes.
function l.olist(t)  
  local u={}; for k,v in pairs(t) do l.push(u, l.fmt("%s", l.o(v))) end; return u end

-- `okeys(t:dict) : str`   
-- Generate a show string for tables with symboloc indexes. Skip private keys; i.e.
-- those starting with "_".
function l.okeys(t)  
  local u={} 
  for k,v in pairs(t) do 
    if not tostring(k):find"^_" then l.push(u, l.fmt(":%s %s", k,l.o(v))) end end; 
  return l.sort(u) end

-- ### Strings to things

-- `coerce(s:str) : thing`    
function l.coerce(s,    also)
  if type(s) ~= "string" then return s end
  also = function(s) return s=="true" or s ~="false" and s end 
  return math.tointeger(s) or tonumber(s) or also(s:match"^%s*(.-)%s*$") end 

-- `coerces(s:str) : list[thing]`
-- Coerce everything inside a comma-seperated string.
function l.coerces(s,    t)
  t={}; for s1 in s:gsub("%s+", ""):gmatch("([^,]+)") do t[1+#t]=l.coerce(s1) end
  return t end

-- Iterator `csv(file:str) : list[thing]`
function l.csv(file)
  file = file=="-" and io.stdin or io.input(file)
  return function(      s)
    s = io.read()
    if s then return l.coerces(s) else io.close(file) end end end

-- `settings(s:tr) : dict`  
-- For any line containing `--(key) ... = value`, generate `key=coerce(value)` .
function l.settings(s,     t)
  t={}
  for k,s1 in s:gmatch("[-][-]([%S]+)[^=]+=[%s]*([%S]+)[.]*\n") do t[k] = l.coerce(s1) end
  return t end

------------------------------------------------------------------------------
-- ## Start-up Actions
local eg={}
local copy,o,oo,push=l.copy,l.o,l.oo,l.oush

eg["actions"] = function(_) 
  print"lua sandbox.lua --[all,copy,cohen,train,bins] [ARG]" end

eg["-h"] = function(x) print(l.help) end

eg["-b"] = function(x) the.bins=  x end
eg["-c"] = function(x) the.cohen= x end
eg["-f"] = function(x) the.fmt=   x end
eg["-s"] = function(x) the.seed=  x end
eg["-t"] = function(x) the.train= x end

eg["--all"] = function(_,    reset,fails)
  fails,reset = 0,copy(the)
  for _,x in pairs{"--copy","--cohen","--train","--bins"} do 
    math.randomseed(the.seed) -- setup
    if eg[oo(x)]()==false then fails=fails+1 end
    the = copy(reset) -- tear down
  end 
  os.exit(fails) end 

eg["--copy"] = function(_,     n1,n2,n3) 
  n1,n2 = NUM.new(),NUM.new()
  for i=1,100 do n2:add(n1:add(rand()^2)) end
  n3 = copy(n2)
  for i=1,100 do n3:add(n2:add(n1:add(rand()^2))) end
  for k,v in pairs(n3) do if k ~="_id" then ; assert(v == n2[k] and v == n1[k]) end  end
  n3:add(0.5)
  assert(n2.mu ~= n3.mu) end

eg["--cohen"] = function(_,    u,t) 
    for inc = 1,1.25,0.03 do 
      u,t = NUM.new(), NUM.new()
      for i=1,20 do u:add( inc * t:add(rand()^.5))  end
      print(inc, u:same(t)) end end 

eg["--train"] = function(file,     d) 
  d= DATA.new():import(file or the.train):sort() 
  for i,row in pairs(d.rows) do
    if i==1 or i %25 ==0 then 
      print(l.fmt("%3s\t%.2f\t%s",i, d:chebyshev(row), o(row))) end end end

eg["--clone"] = function(file,     d0,d1) 
  d0= DATA.new():import(file or the.train) 
  d1 = d0:clone(d0.rows)
  for k,col1 in pairs(d1.cols.x) do print""
     print(o(col1))
     print(o(d0.cols.x[k])) end end

eg["--bins"] = function(file,     d,s,n) 
  d= DATA.new():import(file or the.train):sort()
  s,n=0,0;for _,row in pairs(d.rows) do n=n+1; s = s+d:chebyshev(row) end
  print(s/n)
  for col,bins in pairs(d:bins(d.rows)) do
    print""
    for _,bin in pairs(bins) do
      print(l.fmt("%5.3g\t%3s\t%s", bin.y.mu, bin.y.n, bin)) end end  end

eg["--tree"] = function(file,     d,ys) 
  d= DATA.new():import(file or the.train) 
  d:tree(d.rows, d:bins(d.rows)) end
-- ---------------------------------------------------------------------------------------
-- ## Start-up
if   pcall(debug.getlocal, 4, 1) 
then return {DATA=DATA,NUM=NUM,SYM=SYM,BIN=BIN,TREE=TREE,the=the,lib=l,eg=eg}
else the = l.settings(l.help)
     math.randomseed(the.seed or 1234567891)
     for k,v in pairs(arg) do if eg[v] then eg[v](l.coerce(arg[k+1])) end end end

-- <!-- ③   ④   ⑤    ⑥   ⑦   ⑧    ⑨  ①  ②  -->
