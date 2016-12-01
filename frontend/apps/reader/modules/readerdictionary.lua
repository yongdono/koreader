local InputContainer = require("ui/widget/container/inputcontainer")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local JSON = require("json")
local DEBUG = require("dbg")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderDictionary = InputContainer:new{
    data_dir = nil,
    dict_window_list = {},
}

function ReaderDictionary:init()
    self.ui.menu:registerToMainMenu(self)
    self.data_dir = os.getenv("STARDICT_DATA_DIR") or
        DataStorage:getDataDir() .. "/data/dict"
end

function ReaderDictionary:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Dictionary lookup"),
        tap_input = {
            title = _("Enter a word to look up"),
            type = "text",
            callback = function(input)
                self:onLookupWord(input)
            end,
        },
    })
end

function ReaderDictionary:onLookupWord(word, box, highlight)
    self.highlight = highlight
    self:stardictLookup(word, box)
    return true
end

local function tidy_markup(results)
    local cdata_tag = "<!%[CDATA%[(.-)%]%]>"
    local format_escape = "&[29Ib%+]{(.-)}"
    for _, result in ipairs(results) do
        local def = result.definition
        -- preserve the <br> tag for line break
        def = def:gsub("<[bB][rR] ?/?>", "\n")
        -- parse CDATA text in XML
        if def:find(cdata_tag) then
            def = def:gsub(cdata_tag, "%1")
            -- ignore format strings
            while def:find(format_escape) do
                def = def:gsub(format_escape, "%1")
            end
        end
        -- ignore all markup tags
        def = def:gsub("%b<>", "")
        -- strip all leading empty lines/spaces
        def = def:gsub("^%s+", "")
        result.definition = def
    end
    return results
end

function ReaderDictionary:stardictLookup(word, box)
    DEBUG("lookup word:", word, box)
    if word then
        word = require("util").stripePunctuations(word)
        DEBUG("stripped word:", word)
        -- escape quotes and other funny characters in word
        local results_str = nil
        if Device:isAndroid() then
            local A = require("android")
            results_str = A.stdout("./sdcv", "--utf8-input", "--utf8-output",
                    "-nj", word, "--data-dir", self.data_dir)
        else
            local std_out = io.popen("./sdcv --utf8-input --utf8-output -nj "
                .. ("%q"):format(word) .. " --data-dir " .. self.data_dir, "r")
            if std_out then
                results_str = std_out:read("*all")
                std_out:close()
            end
        end
        --DEBUG("result str:", word, results_str)
        local ok, results = pcall(JSON.decode, results_str)
        if ok and results then
            --DEBUG("lookup result table:", word, results)
            self:showDict(word, tidy_markup(results), box)
        else
            DEBUG("JSON data cannot be decoded", results)
            -- dummy results
            results = {
                {
                    dict = "",
                    word = word,
                    definition = _("No definition found."),
                }
            }
            self:showDict(word, results, box)
        end
    end
end

function ReaderDictionary:showDict(word, results, box)
    if results and results[1] then
        DEBUG("showing quick lookup window", word, results)
        self.dict_window = DictQuickLookup:new{
            window_list = self.dict_window_list,
            ui = self.ui,
            highlight = self.highlight,
            dialog = self.dialog,
            -- original lookup word
            word = word,
            results = results,
            dictionary = self.default_dictionary,
            width = Screen:getWidth() - Screen:scaleBySize(80),
            word_box = box,
            -- differentiate between dict and wiki
            wiki = self.wiki,
        }
        table.insert(self.dict_window_list, self.dict_window)
        UIManager:show(self.dict_window)
    end
end

function ReaderDictionary:onUpdateDefaultDict(dict)
    DEBUG("make default dictionary:", dict)
    self.default_dictionary = dict
    UIManager:show(InfoMessage:new{
        text = T(_("%1 is now the default dictionary for this document."), dict),
        timeout = 2,
    })
    return true
end

function ReaderDictionary:onReadSettings(config)
    self.default_dictionary = config:readSetting("default_dictionary")
end

function ReaderDictionary:onSaveSettings()
    DEBUG("save default dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
end

return ReaderDictionary
