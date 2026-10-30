local index = require("config.api_search.local")
local hoogle = require("config.api_search.hoogle")
local function close()
  for _, p in ipairs(Snacks.picker.get()) do
    p:close()
  end
end
local function wait(title)
  assert(vim.wait(15000, function()
    local p = Snacks.picker.get()[1]
    return p and p.opts.title == title and p:items()[1] ~= nil
  end))
  vim.wait(50)
  return Snacks.picker.get()[1]
end
local root = vim.fn.tempname() .. " SDK with spaces"
vim.fn.mkdir(root, "p")
local fixtures = {
  { language = "c", file = "api.h", code = { "int compute(const char *value);" } },
  { language = "cpp", file = "api.hpp", code = { "namespace example {", "int compute(int value);", "}" } },
  { language = "typescript", file = "api.d.ts", code = { "interface Box {", " compute(value: string): number;", "}" } },
  { language = "rust", file = "api.rs", code = { "pub fn compute(value: &str) -> usize { value.len() }" } },
}
for _, f in ipairs(fixtures) do
  vim.fn.writefile(f.code, root .. "/" .. f.file)
  index.index(
    { language = f.language, root = root, file = root .. "/" .. f.file, title = f.language .. " fixture" },
    "compute",
    true
  )
  local p = wait(f.language .. " fixture")
  local item = p:items()[1]
  assert(item.entry.name:find("compute", 1, true))
  assert(item.text:find("value", 1, true))
  close()
end
local settings = vim.g.api_search_config
vim.g.api_search_config = { cpp = { headers = root, include_roots = { root } } }
index.headers("cpp", "compute")
local header_picker = wait("cpp headers")
local selected
for _, item in ipairs(header_picker:items()) do
  if item.text == "api.hpp" then
    selected = item
    break
  end
end
assert(selected, "custom C++ .hpp SDK header missing")
header_picker.opts.confirm(header_picker, selected)
wait("cpp <api.hpp>")
close()
vim.g.api_search_config = settings
vim.fn.mkdir(root .. "/dist", "p")
vim.fn.writefile(
  { 'throw new Error("indexed code must never execute");', "export declare function published(value: string): number;" },
  root .. "/dist/index.d.ts"
)
index.index(
  { language = "typescript", root = root, installed = true, title = "Published package fixture" },
  "published",
  true
)
assert(wait("Published package fixture"):items()[1].entry.name:find("published", 1, true))
close()
local docs = root .. "/std"
vim.fn.mkdir(docs .. "/vec", "p")
vim.fn.writefile({
  '<pre class="item-decl">pub struct Vec&lt;T&gt;</pre><section id="method.push"><h4 class="code-header">pub fn push(&amp;mut self, value: T)</h4></section>',
}, docs .. "/vec/struct.Vec.html")
index.index({ language = "rustdoc", root = docs, module = "vec", title = "rustdoc fixture" }, "push", true)
assert(wait("rustdoc fixture"):items()[1].entry.name == "std::vec::Vec::push")
close()
-- Default standard-library sources must search across headers/modules directly.
vim.fn.writefile({ "int c_first(void);" }, root .. "/stdio.h")
vim.fn.writefile({ "int c_second(void);" }, root .. "/string.h")
vim.fn.writefile({ "namespace fixture { int cpp_first(); }" }, root .. "/vector")
vim.fn.writefile({ "namespace fixture { int cpp_second(); }" }, root .. "/algorithm")
vim.fn.mkdir(docs .. "/iter", "p")
vim.fn.writefile(
  { '<section id="method.map"><h4 class="code-header">pub fn map(&amp;self)</h4></section>' },
  docs .. "/iter/struct.Iterator.html"
)
local original_config = vim.g.api_search_config
vim.g.api_search_config = {
  c = { headers = root, include_roots = { root } },
  cpp = { headers = root, include_roots = { root } },
  rust = {
    docs = docs,
  },
}
local function names(p)
  local found = {}
  for _, item in ipairs(p:items()) do
    found[item.entry.name] = true
  end
  return found
end
require("config.api_search.profiles.c").sources[1].open("")
local found = names(wait("C standard library"))
assert(found.c_first and found.c_second, "C library was restricted to one header")
close()
require("config.api_search.profiles.cpp").sources[1].open("")
found = names(wait("C++ standard library"))
assert(found["fixture::cpp_first"] and found["fixture::cpp_second"], "C++ library was restricted to one header")
close()
require("config.api_search.profiles.cpp").sources[1].open("fixture::cpp_second")
assert(wait("C++ standard library"):items()[1].entry.name == "fixture::cpp_second", "qualified namespace search failed")
close()
require("config.api_search.profiles.rust").sources[1].open("")
found = names(wait("Rust standard library"))
assert(found["std::vec::Vec::push"] and found["std::iter::Iterator::map"], "Rust library was restricted to one module")
close()
vim.g.api_search_config = original_config
local response = vim.json.encode({
  {
    item = "map :: (a -> b) -> [a] -> [b]",
    module = { name = "Prelude" },
    docs = "Map values.",
    url = "https://example.com/map",
  },
})
local operator = hoogle.entries({
  { item = "(<$>) :: Functor f => (a -> b) -> f a -> f b", module = { name = "Prelude" }, docs = "" },
})
assert(operator[1].signature:find("<$>", 1, true), "Haskell operator was stripped as HTML")
local system = vim.system
local requests = 0
vim.system = function(argv, _, callback)
  assert(argv[1] == "curl")
  assert(argv[#argv] == "hoogle=(a -> b) -> [a] -> [b]")
  requests = requests + 1
  vim.schedule(function()
    callback({ code = 0, stdout = response, stderr = "" })
  end)
  return {}
end
hoogle.search("online", "(a -> b) -> [a] -> [b]", true)
local p = wait("Hoogle (online): (a -> b) -> [a] -> [b]")
assert(p:items()[1].entry.name == "Prelude.map")
assert(p.input.filter.pattern == "", "Hoogle results were incorrectly refiltered by the type query")
close()
vim.system = function()
  error("cached query made a network request")
end
hoogle.search("online", "(a -> b) -> [a] -> [b]")
wait("Hoogle (online): (a -> b) -> [a] -> [b]")
close()
assert(requests == 1)
vim.system = system
assert(vim.fn.exists(":ApiIndexRebuild") == 2)
print("All local language backends, rustdoc, Hoogle routing and offline query-cache checks passed")
