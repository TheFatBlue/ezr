#!/usr/bin/env lua
-- <!-- vim:set filetype=lua et : -->

-- ##  Config
 local the = {
  about = {what="ezr: tools for simpler, explainable, AI",
           when=2024,
           who="Tim Menzies",
           license="BSD, 2 paragraph"},
  all = { inf   = 1E32, 
          seed  = 1234567891,               -- random number seed   
          train = "../data/misc/auto93.csv", -- training data    
          fmt   = "%g",
          cohen = -.35},
  bins = {bins=17}}          

local l,eg = {},{all={}}
local abs,log, max, min = math.abs, math.log, math.max, math.min

--[[
## Input Data Format

Sample data for this code can be downloaded from
github.com/timm/ezr/tree/main/data/\*/\*.csv (please ignore the "old"
directory)

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

Internally, rows are sorted by the goal columns. e.g. in the above
rows, the top rows are best (minimal Lbs, max Acc, max Mpg). 

## Coding conventions

- Line width = 90 characters.
- Indentation = 2 characters.
- Methods = yes; Encapsulation = yes; Polymorphism = yes;  but
  inheritance = no  (I'll let other people explain why no inheritance;
  see Hatton [1] and Diedrich [2] 
- Group methods by functionality, not class (e.g. so all the `add` 
  methods of different classes are together).
- In function args
  - 2 blanks denote start of optionalsl
  - 4 blanks denote start of locals.

## Type hints for function arguments

- Function args uses Alfold-style type hints [3].
- Function arguments lists end with return types; e.g. `function most(n1,n2) --> n `
- `z` is anything.
- `t,d,a` are table,array,dict. Arrays have numeric keys; dicts have symbolic keys. 
- `s,n,b` are strings, numbers,booleans. 
- `fun` is a function
- Suffix `s` is a list of things; e.g. `ns` = list of numbers.
- When used as prefixes, these denote types; e.g. `sFile` is a file name that
  is a  string e.g.  `n1,n2` are two numbers
- Classes are UPPER CASE; e.g NUM. Lower case class numbers denote instances; e.g. `num`.
- `rows` = `list[n | s | "?"]`
- `rows` = `list[row]`

[1] Does OO sync with the way we think?
    https://www.cs.kent.edu/~jmaletic/cs69995-PC/papers/Hatton98.pdf
[2] Stop Writing Classes
    https://www.youtube.com/watch?v=o9pEzgHorH0)
[3] Alfold is a small plain in Hungary, so "Alfold" is my name for an lightweight 
    plain version of the  Hungarian prefix notation.
--]]

-- ## Columns 
local SYM,NUM = {},{}

function SYM:new(s,n) --> sym
  return l.new(SYM,{name=s,pos=n,n=0,has={}}) end

function NUM:new(s,n) --> num
  return l.new(NUM,{name=s,pos=n,n=0,w=0,mu=0,m2=0, lo=the.all.inf, hi=-the.all.inf}) end

function SYM:add(z) --> x
  if z ~="?" then self.n=self.n + 1; self.has[z]=(self.has[z] or 0)+1 end end

function SYM:sub(z) --> x
  if z ~="?" then self.n=self.n - 1; self.has[z]=self.has[z] - 1 end end

function NUM:add(n,      d) --> n
  if n ~= "?" then self.n  = self.n + 1
                   d       = n - self.mu
                   self.mu = self.mu + d/self.n
                   self.m2 = self.m2 + d * (n-self.mu)
                   if     n > self.hi then self.hi = n 
                   elseif n < self.lo then self.lo = n end end
  return n end

function NUM:sub(n,     d) --> n
  if n ~= "?" then self.n  = self.n - 1
                   d       = n - self.mu
                   self.mu = self.mu - d/self.n
                   self.m2 = self.m2 - d*(n - self.mu) end
  return n end

function NUM:mid() --> number
  return self.mu end

function SYM:mid(     most,out) --> x
  most=0; for k,v in pairs(self.has) do if v>most then out,most=k,v end end; return out end

function NUM:div() --> number ; returns standard deviation
  return self.n < 2 and 0 or (self.m2/(self.n - 1))^0.5  end

function SYM:div(   e,N)  --> number ; returns entropy
  N=0; for _,v in pairs(self.has) do N = N + v end
  e=0; for _,v in pairs(self.has) do e = e + v/N*log(v/N,2) end
  return -e end

function NUM:norm(x) --> x | 0..1
  return x=="?" and x or (x-self.lo)/(self.hi-self.lo + 1/the.all.inf) end

-- ## Data
local DATA={}
function DATA:new() --> data
  return l.new(DATA,{rows={}, cols={all={},x={},y={},names={}}}) end

function DATA:read(sFile) --> data
  for n,row in l.csv(sFile) do if n==0 then self:head(row) else self:add(row) end end
  return self end

function DATA:head(row,    col) --> nil
  self.cols.names = row
  for pos,name in pairs(row) do 
    if not name:find"X$" then 
      col = l.push(self.cols.all, (name:find"^[A-Z]" and NUM or SYM):new(name,pos)) 
      if     name:find"-$" then col.w=0; l.push(self.y, col) 
      elseif name:find"+$" then col.w=1; l.push(self.y, col) 
      else   l.push(self.x, col) end end end end

function DATA:clone(  rows,    data)  --> data ; new data has same structure as self
  data = DATA:new():head(self.cols.names) 
  for _,row in pairs(rows or {}) do data:add(row) end 
  return data end

function DATA:add(row) --> nil
  l.push(self.rows,row)
  for _,col in pairs(self.cols.all) do 
    if row[col.pos]~="?" then col:add(row[col.pos]) end end end 

function DATA:sort() --> data ; sorts rows by chebyshev, so left-hand-side rows  are better
  table.sort(self.rows, function(a,b) return self:chebyshev(a) < self:chebyshev(b) end)
  return self end

function DATA:chebyshev(row,     d) --> number ; max distance of any goal to best
  d=0; for _,y in pairs(self.cols.y) do d = max(d,abs(y:norm(row[y.pos]) - y.w)) end
  return d end

function DATA:chebyshevs(rows,    n) --> number ; mean chebyshev
  n= NUM:new()
  for _,r in pairs(rows or self.rows) do n:add(self:chebyshev(r)) end; return n end

-- ---------------------------------------------------------------------------------------
eg.data={}

eg.data["--train [?file]:read in  csv data"] = function(train,     d) 
  d = DATA:new():read(train or the.all.train) 
  l.oo(d.cols.x[2]) end

eg.data["--sort:read and sort data"] = function(train)
  for i,row in pairs(DATA:new():read(train or the.all.train):sort().rows) do 
    if i==1 or i%25==0 then print(i, l.o(row)) end end end

-- ## Discretize
local BIN={}

function BIN:new(s,n,  lo,hi,y) --> BIN
  return l.new(BIN,{name=s,pos=n, lo=lo or the.all.inf, 
                    hi=hi or lo or the.all.inf, y=y or NUM:new(s,n)}) end 

function BIN:add(x,y)
  if x ~= "?" then if x < self.lo then self.lo = x end
                   if x > self.hi then self.hi = x end
                   self.y:add(y) end  end

function BIN:__tostring(     lo,hi,s)
  lo,hi,s = self.x.lo, self.x.hi,self.x.name
  if lo == -the.all.inf then return l.fmt("%s <= %g", s,hi) end
  if hi ==  the.all.inf then return l.fmt("%s > %g",  s,lo) end
  if lo ==  hi          then return l.fmt("%s == %s", s,lo) end
  return l.fmt("%g < %s <= %g", lo, s, hi) end

function BIN:selects(rows,     u,lo,hi,x)
  u,lo,hi = {}, self.x.lo, self.y.hi
  for _,row in pairs(rows) do 
    x = row[self.x.pos]
    if x=="?" or lo==hi and lo==x or lo < x and x <= hi then l.push(u,r) end end
  return u end

function SYM:bins(rows,y,_,     t,x) --> array[bin] ; proposes one split per symbol value
  t = {}
  for row in pairs(rows) do
    x = row[self.pos]
    if x ~= "?" then t[x] = t[x] or BIN:new(self.name,self.pos,x) 
                     t[x]:add(x, y(row)) end end
  return t end

function NUM:bins(rows,y,xepsilon,yepsilon) --> nil | [bin1,bin2] ;get binary split of numerics
  local function x(row) return row[self.pos] end
  local function q(z)  return z=="?" and -the.all.inf or z end
  local ys,right0 = {},NUM:new()
  for i,r in pairs(rows) do ys[i] = right0:add(y(r)) end
  return self:num1(l.sort(rows,function(a,b) return q(x(a)) < q(x(b)) end),
                   function(row) return row[self.pos] end,y,
                   BIN:new(self.name,self.pos), right0,
                   xepsilon, yepsilon, self:div(), #rows) end


function NUM:bins1(rows,x,y,left0,right0,xepsilon,yepsilon,min,got,ys,       left,right)
  y0,x0 = ys[1], x(rows[1])
  yn,xn = ys[#rows], x(rows[#rows]) 
  for i,row in pairs(rows) do
    if x(row) == "?" then got = got - 1 else
      left0:add(x(row), ys[i])
      right0:sub(ys[i])
      if left0.y.n >= got^0.5 and right0.n >= got^0.5 then -- enough items
        if x(row) ~= x(rows[i+1]) then -- there is a break
          x1,x2,x3 = x(row) - x0, left0.hi - left0.lo,  xn - x(row) -- is there anything about the size of the break?
          y1,y2,y3 = ys[i] - y0, right0.hi - right0.lo, yn - ys[i]  -- 
          if abs(left0.y:mid() - right0:mid()) > yepsilon then -- enough y separation
            if left0.lo - x(rows[1]) >= xepsilon and left0.hi - left0.lo > xepsilon and x(rows[#rows]) - left0.hi >= xepsilon then
              local tmp = (left0.y.n*left0.y:div() + right0.n*right0:div()) / got
              if tmp < min then 
                min,left,right = tmp, l.copy(left0), l.copy(right0) end end end end end end end 
  left.lo = -the.all.inf
  if left then return {left,BIN:new(self.name,self.pos, left.hi,the.all.inf,right)} end end

-- ## Tree
local TREE={}

function TREE:new(here,lvl,s,n,lo,hi,mu)
  return l.new(TREE,{lvl=lvl or 0, bin=BIN:new(s,n,lo,hi), 
                     mu=mu or 0, here=here, _kids={}})  end

function TREE:__tostring() 
  return l.fmt("%.2f\t%5s\t%s%s", self.mu, #self.here.rows, 
                       ("|.. "):rep(self.lvl-1), self.lvl==0 and "" or self.bin) end

function TREE:visit(fun) 
  fun = fun or print
  fun(self)
  for _,kid in pairs(self._kids) do kid:visit(fun) end end 

function DATA:tree(     _grow)
  function _grow(rows,stop,lvl,name,pos,lo,hi,     tree,sub,_grow)
    tree = TREE:new(self:clone(rows), lvl,name,pos,lo,hi,self:chebyshevs(rows))
    for _,bin in pairs(self:bins(rows):spitter().bins) do
      sub = bin:selects(rows)
      if #sub < #rows and #sub > stop then
        l.push(tree._kids, _grow(sub,stop,lvl+1,bin.name,bin.pos,bin.x.lo,bin.x.hi)) end end
    return tree 
  end
  return _grow(self.rows,(#self.rows)^0.5,0) end

function DATA:splitter(      lo,w,n,out,tmp)
  lo = the.all.inf
  for _,col in pairs(self.cols.x) do
    w,n,tmp,out = 0,0,{},out or col
    for _,bin in pairs(col.bins) do w=w+bin.y.n*bin.y:div(); n=n+bin.y.n; l.push(tmp,bin) end
    if w/n < lo then lo, out = w/n, col end
    table.sort(tmp, function(a,b) return a.y.mu < b.y.mu end)
    col.bins = tmp end 
  return out end  

local function _bestBins(bins,      most,best,n,xpect)
  xpect,n,best = 0,0,nil
  for _,bin in pairs(bins) do 
    best = best or bin
    n    = n   + bin.y.n
    xpect  = xpect + bin.y:div() 
    if bin.y:mid() > most then most,best = bin.y:mid(),bin end end
  best.best=true
  return bins, xpect/n end

-- ## Lib
function l.rand(...) --> n
  return math.random(...) end

function l.sort(a,fun) --> a
  table.sort(a,fun); return a end

l.fmt = string.format --> s

function l.printf(s,...) --> nil
  print(string.format(s,...)) end

function l.push(t,z)  --> x
  t[1+#t]=z; return z end

function l.ocat(a,    u) --> array[str]
  u={}; for _,v in pairs(a) do l.push(u,l.o(v)) end; return u end

function l.okat(d,    u) --> array[str]
  u={}
  for k,v in pairs(d) do 
    if not tostring(k):find"^_" then l.push(u,l.fmt("%s:%s",k,l.o(v))) end end
  table.sort(u)
  return u end

function l.o(t)  --> t
  if type(t)== "number" then return l.fmt(the.all.fmt,t) end
  if type(t)~= "table"  then return tostring(t) end
  return "("..table.concat(#t==0 and l.okat(t) or l.ocat(t),", ")..")" end

function l.oo(t) --> t
  print(l.o(t)); return t end

function l.coerce(s,    fun) --> number | str | boolean
  if type(s) ~= "string" then return s end
  fun = function(s) return s=="true" or s ~="false" and s end 
  return math.tointeger(s) or tonumber(s) or fun(s:match"^%s*(.-)%s*$") end 

function l.csv(sFile,   n) --> interator
  sFile = sFile=="-" and io.stdin or io.input(sFile)
  n = -1
  return function(      s,t) --> row
    s = io.read()
    if s then 
       n = n + 1
       t={};for x in s:gsub("%s+", ""):gmatch("([^,]+)") do t[1+#t]=l.coerce(x) end
       return n,t 
    else io.close(sFile) end end end 

function l.copy(t,  u)
  if type(t) ~= "table" then return t end
  u={}; for k,v in pairs(t) do u[l.copy(k)] = l.copy(v) end
  return setmetatable(u, getmetatable(t)) end

function l.new(dmeta,d) --> instance ;(a) create 1 instance; (b) enable class polymorphism
  dmeta.__index=dmeta; setmetatable(d,dmeta); return d end

function l.keys(t,    n,u)
  u={}; for k,_ in pairs(t) do l.push(u,k) end;
  n,u=0,l.sort(u)
  return function () 
    if n < #u then n=n+1; return u[n], t[u[n]] end end end  
      
function l.main(out,      fails,here)
  fails,here = 0,"all"
  for n,s in pairs(arg) do
    here = eg[s] and s or here
    for help,fun in pairs(eg[here]) do
      print(n,s,here,help)
      if help:find("^("..s.."):") then 
        fails = fails + (fun(l.coerce(arg[n+1])) == false and 1 or 0) end end end 
  return fails > 0 and os.exit(fails) or out end

eg.all[ "--copy:testing deep copy"] = function(_,     n1,n2,n3) 
  n1,n2 = NUM:new(),NUM:new()
  for i=1,100 do n2:add(n1:add(l.rand()^2)) end
  n3 = l.copy(n2)
  for i=1,100 do n3:add(n2:add(n1:add(l.rand()^2))) end
  for k,v in pairs(n3) do if k ~="_id" then ; assert(v == n2[k] and v == n1[k]) end end
  n3:add(0.5)
  assert(n2.mu ~= n3.mu) end

eg.all["-h:show help"]= function(_,     pre,left,right)
  print(l.fmt("\n%s\n(c) %s %s %s",
              the.about.what, the.about.when, the.about.who, the.about.license))
  print("\nUSAGE: ezr [group] [--flag] [ARG]\n\nCOMMANDS:")
  for here,_ in l.keys(eg) do
    pre = l.fmt("ezr %s", here=="all" and "" or here)
    for help,_ in l.keys(eg[here]) do
      left, right = help:match("^(.-):(.*)$")
      l.printf("  %-10s %s %s",pre,left,right)
      pre="" end end end

-- ---------------------------------------------------------------------------------------
return l.main{NUM=NUM, SYM=SYM, DATA=DATA, TREE=TREE, BIN=BIN, lib=l}
