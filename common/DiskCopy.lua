local Ansi       = require('opus.ansi')
local Config     = require('opus.config')
local Event      = require('opus.event')
local UI         = require('opus.ui')
local Util       = require('opus.util')

local colors     = _G.colors
local fs         = _G.fs
local peripheral = _G.peripheral

local drives = { }
if peripheral.getType('left') == 'drive' then
		drives.left = Util.shallowCopy(peripheral.wrap('left'))
		drives.left.name = 'left'
end
if peripheral.getType('right') == 'drive' then
	drives.right = Util.shallowCopy(peripheral.wrap('right'))
	drives.right.name = 'right'
end

peripheral.find('drive', function(n, v)
	if not drives.left then
		drives.left = Util.shallowCopy(v)
		drives.left.name = n
	elseif not drives.right then
		drives.right = Util.shallowCopy(v)
		drives.right.name = n
	end
end)

if not (drives.left and drives.right) then
	error('Two drives are required')
end

local COPY_LEFT  = 1
local COPY_RIGHT = 2
local directions = {
	[ COPY_LEFT  ] = { text = '-->>' },
	[ COPY_RIGHT ] = { text = '<<--' },
}

local config = Config.load('DiskCopy', {
	eject = true,
	automatic = false,
	copyDir = COPY_LEFT
})

local page = UI.Page {
	linfo = UI.Window {
		x = 2, y = 2, ey = 5, width = 18,
	},
	rinfo = UI.Window {
		x = -19, y = 2, ey = 5, width = 18,
	},
	dir = UI.Button {
		x = 17, y = 6, width = 6,
		event = 'change_dir',
	},
	progress = UI.ProgressBar {
		x = 2, ex = -2, y = -4,
		backgroundColor = colors.black,
	},
	ejectText = UI.Text {
		x = 2, y = -2,
		value = 'Eject'
	},
	eject = UI.Checkbox {
		x = 8, y = -2,
	},
	automaticText = UI.Text {
		x = 12, y = -2,
		value = 'Copy automatically'
	},
	automatic = UI.Checkbox {
		x = 31, y = -2,
	},
	copyButton = UI.Button {
		x = -7, y = -2,
		text = 'Copy',
		event = 'copy',
		inactive = true,
	},
	warning = UI.Text {
		x = 2, ex = -2, y = -1,
		align = 'center',
		textColor = colors.orange,
	},
	notification = UI.Notification { },
}

function page:enable()
	Util.merge(self.dir, directions[config.copyDir])

	self.eject.value = config.eject
	self.automatic.value = config.automatic

	self.dir.x = math.floor((self.width / 2) - 3) + 1

	UI.Page.enable(self)
end

local function isValid(drive)
	return drive.isDiskPresent() and drive.getMountPath()
end

local function needsLabel(drive)
	return drive.isDiskPresent() and not drive.getMountPath() and not drive.getAudioTitle()
end

function page:drawInfo(drive, textArea)
	local function getLabel()
		return not drive.isDiskPresent() and 'empty' or
		not drive.getMountPath() and 'invalid' or
		drive.getDiskLabel() or 'unlabeled'
	end

	local function getUsed()
		return isValid(drive) and fs.getSize(drive.getMountPath(), true) or 0
	end

	local function getFree()
		return isValid(drive) and fs.getFreeSpace(drive.getMountPath()) or 0
	end

	textArea:setCursorPos(1, 1)
	textArea:print(string.format('Drive: %s%s%s\nLabel: %s%s%s\nUsed:  %s%s%s\nFree:  %s%s%s',
		Ansi.yellow, drive.name, Ansi.reset,
		isValid(drive) and Ansi.yellow or Ansi.orange, getLabel():sub(1, 10), Ansi.reset,
		Ansi.yellow, Util.toBytes(getUsed()), Ansi.reset,
		Ansi.yellow, Util.toBytes(getFree()), Ansi.reset))
end

function page:scan()
	local showWarning = needsLabel(drives.left) or needsLabel(drives.right)
	local valid = isValid(drives.left) and isValid(drives.right)

	self.warning.value = showWarning and 'Computers must be labeled'
	self.copyButton.inactive = not valid

	self:draw()
	self.progress:centeredWrite(1, 'Analyzing Disks..')
	self.progress:sync()

	self:drawInfo(drives.left, self.linfo)
	self:drawInfo(drives.right, self.rinfo)

	self.progress:clear()
end

function page:copy()
	local sdrive = config.copyDir == COPY_LEFT and drives.left or drives.right
	local tdrive = config.copyDir == COPY_LEFT and drives.right or drives.left

	local throttle = Util.throttle()
	local sourceFiles, targetFiles = { }, { }

	local function getListing(mountPath, path, files)
		for _,f in pairs(fs.list(path)) do
			local file = fs.combine(path, f)
			if not fs.isReadOnly(file) then
				files[string.sub(file, #mountPath + 1)] = true
				if fs.isDir(file) then
					getListing(mountPath, file, files)
				end
			end
		end
		throttle()
	end

	self.progress:centeredWrite(1, 'Computing..')
	self.progress:sync()

	getListing(sdrive.getMountPath(), sdrive.getMountPath(), sourceFiles)
	getListing(tdrive.getMountPath(), tdrive.getMountPath(), targetFiles)

	local copied = 0
	local totalFiles = Util.size(sourceFiles)

	local function rawCopy(source, target)
		if fs.isDir(source) then
			copied = copied + 1
			if not fs.exists(target) then
				fs.makeDir(target)
			end
			for _,f in pairs(fs.list(source)) do
				rawCopy(fs.combine(source, f), fs.combine(target, f))
			end

		else
			if fs.exists(target) then
				fs.delete(target)
			end

			fs.copy(source, target)
			copied = copied + 1
			self.progress.value = copied * 100 / totalFiles
			self.progress:draw()
			self.progress:sync()
		end
		throttle()
	end

	local function cleanup()
		for k in pairs(targetFiles) do
			if not sourceFiles[k] then
				fs.delete(fs.combine(tdrive.getMountPath(), k))
			end
		end
	end

	self.progress:clear()
	rawCopy(sdrive.getMountPath(), tdrive.getMountPath())
	cleanup()
	self.progress:centeredWrite(1, 'Copy Complete', colors.lime, colors.black)
	self.progress:sync()

	self.progress.value = 0
	self.progress:clear()

	self:scan()

	if config.eject then
		tdrive.ejectDisk()
	end
end

function page:eventHandler(event)
	if event.type == 'change_dir' then
		config.copyDir = (config.copyDir) % 2 + 1
		Util.merge(self.dir, directions[config.copyDir])
		Config.update('DiskCopy', config)
		self.dir:draw()

	elseif event.type == 'copy' then
		self:copy()

	elseif event.type == 'checkbox_change' then
		if event.element == self.eject then
			config.eject = not not event.checked
		elseif event.element == self.automatic then
			config.automatic = not not event.checked
		end

		Config.update('DiskCopy', config)
		event.element:draw()

	else
		return UI.Page.eventHandler(self, event)
	end
	return true
end

Event.on("disk", function()
	page:scan()
	page:sync()

	if config.automatic and not page.copyButton.inactive then
		page:copy()
	end
end)

Event.on("disk_eject", function()
	page:scan()
	page:sync()
end)

Event.onTimeout(.2, function()
	page:scan()
	page:sync()
end)

UI:setPage(page)
UI:pullEvents()
