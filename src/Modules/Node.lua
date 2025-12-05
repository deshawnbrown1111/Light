local module = {}

function module.new(cell, g, h, parent)
    return {
        cell = cell,
        g = g,
        h = h,
        f = g + h,
        parent = parent
    }
end

function module.key(cell)
    return cell.X .. "," .. cell.Y .. "," .. cell.Z
end

return module
