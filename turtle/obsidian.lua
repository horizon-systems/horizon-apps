local Point = require('opus.point')
local Util  = require('opus.util')

local os     = _G.os
local turtle = _G.turtle

local checkedNodes, nodes

local function addNode(node)

	for i = 0, 3 do
		local hi = turtle.getHeadingInfo(i)
		local testNode = { x = node.x + hi.xd, z = node.z + hi.zd }

		local key = table.concat({ testNode.x, testNode.z }, ':')
		if not checkedNodes[key] then
			nodes[key] = testNode
		end
	end
end

local function findObsidian()
	repeat
		local node = { x = turtle.point.x, z = turtle.point.z }
		local key = table.concat({ node.x, node.z }, ':')

		checkedNodes[key] = true
		nodes[key] = nil

		local _,b = turtle.inspectDown()
		if b and (b.name == 'minecraft:lava' or b.name == 'minecraft:flowing_lava') then
			if turtle.select('minecraft:water_bucket') then
				while true do
					if turtle.up() then
						break
					end
					print('stuck')
				end
				turtle.placeDown()
				os.sleep(2)
				turtle.placeDown()
				turtle.down()
				turtle.select(1)
				_, b = turtle.inspectDown()
			end
		end

		if turtle.getItemCount(16) > 0 then
			print('Inventory full')
			print('Enter to continue...')
			_G.read()
		end

		if b and b.name == 'minecraft:obsidian' then
			turtle.digDown()
			addNode(node)
		else
			turtle.digDown()
		end

		print(string.format('%d nodes remaining', Util.size(nodes)))

		if Util.size(nodes) == 0 then
			break
		end

		node = Point.closest(turtle.point, nodes)
		if not turtle.go(node) then
			break
		end
	until turtle.isAborted()
end

turtle.run(function()
	turtle.reset()
	turtle.set({ digPolicy = 'dig' })

	local s, m = pcall(function()
		repeat
			checkedNodes = { }
			nodes = { }

			local _,b = turtle.inspectDown()
			if not b or b.name ~= 'minecraft:obsidian' then
				break
			end

			findObsidian()
			if not turtle.select('minecraft:water_bucket') then
				break
			end
			turtle.go({ x = 0, z = 0 })
			turtle.placeDown()
			os.sleep(2)
			turtle.placeDown()
			turtle.down()
			turtle.select(1)
		until turtle.isAborted()
	end)

	if not s and m then
		error(m)
	end

	turtle.go({ x = 0, y = 0, z = 0, heading = 0 })
end)
