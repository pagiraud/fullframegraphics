--[[
abstract-section – move an "abstract" section into document metadata

Copyright: © 2024 Pierre-Amiel Giraud
License:   GNU GPL v3 – see LICENSE file for details
This filter is freely built upon Ojdo’s code. See this page : https://www.ojdo.de/wp/2018/06/finally-the-definitive-full-frame-graphic-commands-for-beamer-in-latex/
]]

if FORMAT ~= "beamer" then
  print("This filter only works with Beamer. Sorry.")
  return
end

--Because the pandoc.image functions were introduced with Pandoc 3.1.13
if PANDOC_VERSION < {3,1,13} then
  print("You need at least Pandoc 3.1.13 to use this filter. Please upgrade.")
  return
end

--Check context to know whether the filter is used in Quarto
local function inQuarto()
  local is_inquarto
  if quarto and quarto.version then
    is_inquarto = true
  else
    is_inquarto = false
  end
  return is_inquarto
end

local isInQuarto = inQuarto()

--[[
Variables definitions
--]]

-- Default values that can be modified in the YAML header.
local f = {
  ["adjustimage"] = "true",
  ["adjustimageclass"] = "adjust",
  ["noadjustimageclass"] = "noadjust",
  ["captionposition"] = "south east",
  ["anchorposition"] = "south east",
  ["fontsize"] = "tiny",
  ["textcolor"] = "white",
  ["fillcolor"] = "black",
  ["fillopacity"] = ".5",
  ["textopacity"] = "1",
  ["innersep"] = "2pt",
  ["textheight"] = "1ex",
  ["textdepth"] = ".25ex",
  }

-- Initiates the frameratio variable
local frameratio

-- Defines the different common parts of the tikzpicture environment
local ffgEnvirFirst = [[
\begin{tikzpicture}[remember picture,overlay]%
  \node[at=(current page.center)] {%
    \includegraphics[]]
local ffgEnvirSecond = [[,keepaspectratio]{]]
local ffgEnvirThird = [[}%
  };%
]]
local ffgEnvirLast = [[

\end{tikzpicture}%
  ]]

--[[
Loading needed Latex Packages
--]]

local neededPackages = [[
\makeatletter
\@ifpackageloaded{tikz}{}{\usepackage{tikz}}
\makeatother
\makeatletter
\@ifpackageloaded{adjustbox}{}{\usepackage[export]{adjustbox}}
\makeatother
]]

--[[
Functions definitions
--]]

--Just a shorthand because the filter uses it a lot
local function latex(str)
  return pandoc.RawInline('latex', str)
end

--For the Blocks function. Finds figures (with or without captions) in a frame with the fullframegraphic class
local function is_figure_in_fullframegraphic_frame(frame, figure)
  if frame and frame.t == 'Header'
    and figure and (figure.t == 'Figure' or figure.t == 'Para')
    and frame.classes[1] == "fullframegraphic" then
    return figure.t
  end
end

--In the metadata, the aspectratio is declared as a string (e.g. 169).
--Reads the ratio according to the Beamer documentation (e.g. 169 => 16/9)
local function convertRatio(fR,aR)
  if aR == nil then
    fR = 4/3
  else
    aR = pandoc.utils.stringify(aR)
    if aR == "141" then
      fR = 1.41
    elseif string.len(aR) == 2 then
     fR = tonumber(string.sub(aR,1,1))/tonumber(string.sub(aR,2,2))
    elseif string.len(aR) == 3 then
      fR = tonumber(string.sub(aR,1,2))/tonumber(string.sub(aR,3,3))
    elseif string.len(aR) == 4 then
      fR = tonumber(string.sub(aR,1,2))/tonumber(string.sub(aR,3,4))
    else
      fR = tonumber(aR)
    end
  end
  return fR
end

-- Determines whether the image size needs to be adjusted
local function adjustNoAdjust (cls)
  if cls == nil then
    if f.adjustimage == "true" then
      cls = f.adjustimageclass
    else
      cls = f.noadjustimageclass
    end
  end
  return cls
end

--Sends options to the \includegraphics command to eventually adjust the image size.
--Actually it just lets it go out of frame
local function cropImage(img, class, fR)
  local toolarge
  local tootall
--Quarto and Pandoc don’t use the same Latex preamble, and that affects the \includegraphics function.
--The filter needs to adapt to get the same result with both software.
  if isInQuarto then
    toolarge = "min height=\\paperheight"
    tootall = "min width=\\paperwidth"
  else
    tootall = "min height=\\paperheight, max width=\\paperwidth"
    toolarge = "min width=\\paperwidth, max height=\\paperheight"
  end
  local imageFile = io.open(img)
  local imageStream = imageFile:read('*a')
  imageFile:close()
  local imageSize = pandoc.image.size(imageStream)
  local imageRatio = imageSize.width/imageSize.height
  local ratioParameter
  if class == f.noadjustimageclass then
    ratioParameter = "height=\\paperheight,width=\\paperwidth"
   elseif imageRatio <= fR then
    ratioParameter = tootall
  elseif imageRatio > fR then
    ratioParameter = toolarge
  end
  return ratioParameter
end

--Updates default preferences with metadatas.
--Sends tikzset preferences to Latex.
local function parameters(meta)
frameratio = convertRatio(frameratio,meta.aspectratio)
  if meta.fullframegraphics ~= nil then
    for k, v in pairs(meta.fullframegraphics) do f[k] = pandoc.utils.stringify(v) end
  end

  local ffgcaption = [[
\tikzset{ffgcaption/.style={%
  anchor=]] .. f.anchorposition .. ",font=\\" .. f.fontsize .. [[,
  text=]] .. f.textcolor .. ",fill=" .. f.fillcolor .. [[,
  fill opacity=]] .. f.fillopacity .. ",text opacity=" .. f.textopacity .. ",inner sep=" .. f.innersep .. [[,
  text height=]] .. f.textheight .. ",text depth=" .. f.textdepth .. [[}}
]]

--Thanks to code in fonts-and-alignment.lua
    local includes = meta['header-includes']
  -- Default to a List
  includes = includes or pandoc.List({ })
  -- If not a List make it one!
  if 'List' ~= pandoc.utils.type(includes) then
    includes = pandoc.List({ includes })
  end
  -- Add the ulem usepackage LaTeX statement
  includes:insert(pandoc.RawBlock('beamer', neededPackages))
  includes:insert(pandoc.RawBlock('beamer', ffgcaption))
  -- Make sure Pandoc gets our changes
  meta['header-includes'] = includes
--End of code from fonts-and-alignment.lua
  return meta
end

--Builds the tikzpicture environment
local function fullframegraphic(elem)
  local caption = "\\node[at=(current page." .. f.captionposition .. "),ffgcaption] {" .. pandoc.utils.stringify(pandoc.Span(elem.content[1].content[1].caption)) .. "};%"
  local class = adjustNoAdjust(elem.content[1].content[1].classes[1])
  local image = elem.content[1].content[1].src
  local ratioParameter = cropImage(image,class,frameratio)
  return pandoc.Para{
    latex(ffgEnvirFirst), latex(ratioParameter), latex(ffgEnvirSecond), image, latex(ffgEnvirThird), latex(caption), latex(ffgEnvirLast)
  }
end

--Same if there is no caption.
local function fullframegraphicNoCaption(elem)
  local class = adjustNoAdjust(elem.content[1].classes[1])
  local image = elem.content[1].src
  local ratioParameter = cropImage(image,class,frameratio)
  return pandoc.Para{
    latex(ffgEnvirFirst), latex(ratioParameter), latex(ffgEnvirSecond), image, latex(ffgEnvirThird), latex(ffgEnvirLast)
  }
end

--Determines whether something should be done at all.
--Strips out the frame title and sets the frame class to plain.
--Uses the good tikzpicture environment.
local function bblocks (blocks)
  local figuretype
  -- Go from end to start to avoid problems with shifting indices.
  for i = #blocks-1, 1, -1 do
    figuretype = is_figure_in_fullframegraphic_frame(blocks[i], blocks[i+1])
    if figuretype == "Figure" then
      blocks[i].content = ""
      blocks[i].classes[2] = "plain"
      blocks[i+1] = fullframegraphic(blocks[i+1])
    elseif figuretype == "Para" then
      blocks[i].content = ""
      blocks[i].classes[2] = "plain"
      blocks[i+1] = fullframegraphicNoCaption(blocks[i+1])
    end
  end
  return blocks
end

-- Meta before blocks (this way so aspectratio from metadata is available.)
return {{Meta = parameters}, {Blocks = bblocks}}
