local module = {}

function module.new()
    return {
        heap = {},
        size = 0
    }
end

function module.push(pq, item, priority)
    pq.size = pq.size + 1
    pq.heap[pq.size] = {item = item, priority = priority}
    local i = pq.size
    while i > 1 do
        local parent = math.floor(i / 2)
        if pq.heap[parent].priority <= pq.heap[i].priority then break end
        pq.heap[parent], pq.heap[i] = pq.heap[i], pq.heap[parent]
        i = parent
    end
end

function module.pop(pq)
    if pq.size == 0 then return nil end
    local result = pq.heap[1].item
    pq.heap[1] = pq.heap[pq.size]
    pq.heap[pq.size] = nil
    pq.size = pq.size - 1
    local i = 1
    while true do
        local left = i * 2
        local right = i * 2 + 1
        local smallest = i
        if left <= pq.size and pq.heap[left].priority < pq.heap[smallest].priority then
            smallest = left
        end
        if right <= pq.size and pq.heap[right].priority < pq.heap[smallest].priority then
            smallest = right
        end
        if smallest == i then break end
        pq.heap[i], pq.heap[smallest] = pq.heap[smallest], pq.heap[i]
        i = smallest
    end
    return result
end

function module.isEmpty(pq)
    return pq.size == 0
end

return module
