-- System functions

module ("dist.utils", package.seeall)

local sys = require "dist.sys"

-- Returns a deep copy of 'table' with reference to the same metadata table.
-- Source: http://lua-users.org/wiki/CopyTable
function deepcopy(object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

-- Return deep copy of table 'array', containing only items for which 'predicate_fn' returns true.
function filter(array, predicate_fn)
    assert(type(array) == "table", "utils.filter: Argument 'array' is not a table.")
    assert(type(predicate_fn) == "function", "utils.filter: Argument 'predicate_fn' is not a function.")
    local tbl = {}
    for _,v in pairs(array) do
        if predicate_fn(v) == true then table.insert(tbl, deepcopy(v)) end
    end
    return tbl
end

-- Return deep copy of table 'array', sorted according to the 'compare_fn' function.
function sort(array, compare_fn)
    assert(type(array) == "table", "utils.sort: Argument 'array' is not a table.")
    assert(type(compare_fn) == "function", "utils.sort: Argument 'compare_fn' is not a function.")
    local tbl = deepcopy(array)
    table.sort(tbl, compare_fn)
    return tbl
end

-- Return single line string consisting of values in 'tbl' separated by comma.
-- Used for printing the dependencies/provides/conflicts.
function table_tostring(tbl, label)
    assert(type(tbl) == "table", "utils.table_tostring: Argument 'tbl' is not a table.")
    local str = ""
    for k,v in pairs(tbl) do
        if type(v) == "table" then
            str = str .. table_tostring(v, k)
        else
            if label ~= nil then
                str = str .. tostring(v) .. " [" .. tostring(label) .. "]" .. ", "
            else
                str = str .. tostring(v) .. ", "
            end
        end
    end
    return str
end

-- Return table parsed from the string, retaining only values of number, string,
-- boolean or table type.
function parse_table(str)
    assert(type(str) == "string", "luadist.parse_table: Argument 'str' is not a string.")

    -- Retain only number, string, boolean & table values in table 'tbl'.
    local function filter_table(tbl)
        tbl = deepcopy(tbl)
        local tmp_tbl = {}
        for k,v in pairs(tbl) do
            if type(v) == "table" then
                tmp_tbl[k] = filter_table(v)
            elseif type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
                tmp_tbl[k] = v
            end
        end
        return tmp_tbl
    end

    str = "return " .. str

    local eval, err = loadstring(str)
    if not eval then return nil, err end

    local evaled_table = eval()
    return filter_table(evaled_table)
end

-- Return whether the 'cache_timeout' for 'file' has expired.
function cache_timeout_expired(cache_timeout, file)
    assert(type(cache_timeout) == "number", "utils.cache_timeout_expired: Argument 'cache_timeout' is not a number.")
    assert(type(file) == "string", "utils.cache_timeout_expired: Argument 'file' is not a string.")
    return sys.last_modification_time(file) + cache_timeout < sys.current_time()
end

-- Return the string 'str', with all magic (pattern) characters escaped.
function escape(str)
    assert(type(str) == "string", "utils.escape: Argument 'str' is not a string.")
    local escaped = str:gsub('[%-%.%+%[%]%(%)%^%%%?%*%^%$]','%%%1')
    return escaped
end

-- If the table 'array' contains another table with specified key associated with
-- specified value, then return index of that another table, else return nil.
function find_index(array, key, value)
    assert(type(array) == "table", "utils.contains: Argument 'array' is not a table.")
    assert(type(key) == "string", "utils.contains: Argument 'key' is not a string.")

    for idx, item in pairs(array) do
        if type(item) == "table" and item[key] and type(item[key]) == type(value) and item[key] == value then return idx end
    end

    return nil
end
