import Foundation

/// One velocity layer inside one articulation. Offsets are into `LayerBank.storage`.
nonisolated struct LayerCell {
    var offset: Int32 = 0
    var count: Int32 = 0
    var velocityHi: Float = 1
    var velocityRef: Float = 1
    var curveAtRef: Float = 1
}

/// Copied onto the track slot when `swapLayers` is applied. The render thread reads these
/// pointers and does not touch the class.
nonisolated struct SlotLayer {
    var token: UInt = 0
    var storage: UnsafeMutablePointer<Float>? = nil
    var curve: UnsafePointer<Float>? = nil
    var cells: UnsafePointer<LayerCell>? = nil
    var articulationCount: Int32 = 0
    var layerCount: Int32 = 0
    var roundRobin: Int32 = 0
    var useCurve: Int32 = 0
}

/// One allocation for every articulation × layer × round-robin, plus a 128-gain curve.
/// Freed on the main actor when the retire ring releases the `Unmanaged` retain.
nonisolated final class LayerBank: @unchecked Sendable {
    let storage: UnsafeMutablePointer<Float>
    let storageCount: Int
    let curve: UnsafeMutablePointer<Float>
    let cells: UnsafeMutablePointer<LayerCell>
    let cellCount: Int
    let articulationCount: Int
    let layerCount: Int
    let roundRobin: Int
    let useCurve: Int32

    private init(
        storage: UnsafeMutablePointer<Float>,
        storageCount: Int,
        curve: UnsafeMutablePointer<Float>,
        cells: UnsafeMutablePointer<LayerCell>,
        cellCount: Int,
        articulationCount: Int,
        layerCount: Int,
        roundRobin: Int,
        useCurve: Int32
    ) {
        self.storage = storage
        self.storageCount = storageCount
        self.curve = curve
        self.cells = cells
        self.cellCount = cellCount
        self.articulationCount = articulationCount
        self.layerCount = layerCount
        self.roundRobin = roundRobin
        self.useCurve = useCurve
    }

    deinit {
        storage.deinitialize(count: storageCount)
        storage.deallocate()
        curve.deinitialize(count: 128)
        curve.deallocate()
        cells.deinitialize(count: cellCount)
        cells.deallocate()
    }

    func slotLayer(token: UInt) -> SlotLayer {
        SlotLayer(
            token: token,
            storage: storage,
            curve: UnsafePointer(curve),
            cells: UnsafePointer(cells),
            articulationCount: Int32(articulationCount),
            layerCount: Int32(layerCount),
            roundRobin: Int32(roundRobin),
            useCurve: useCurve
        )
    }

    func buffer(articulation: Int, layer: Int, roundRobin index: Int) -> [Float] {
        let slot = ((articulation * layerCount) + layer) * roundRobin + index
        guard slot >= 0, slot < cellCount else { return [] }
        let cell = cells[slot]
        let count = Int(cell.count)
        guard count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: storage.advanced(by: Int(cell.offset)), count: count))
    }

    /// Rectangular `[articulation][layer][roundRobin]` buffers. Empty cells become one zero.
    static func make(
        articulations: [[[[Float]]]],
        velocityHi: [Float],
        velocityRef: [Float],
        curve: [Float],
        useCurve: Bool
    ) -> LayerBank {
        let arts = max(1, articulations.count)
        let layers = max(1, velocityHi.count)
        let robins = max(1, articulations.first?.first?.count ?? 1)
        let cellCount = arts * layers * robins
        var packed: [Float] = []
        packed.reserveCapacity(1024)
        let cellPtr = UnsafeMutablePointer<LayerCell>.allocate(capacity: cellCount)
        cellPtr.initialize(repeating: LayerCell(), count: cellCount)
        var cellIndex = 0
        for art in 0..<arts {
            for layer in 0..<layers {
                let hi = layer < velocityHi.count ? velocityHi[layer] : 1
                let ref = layer < velocityRef.count ? velocityRef[layer] : hi
                let curveIndex = min(127, max(0, Int(ref * 127 + 0.5)))
                let atRef = curveIndex < curve.count ? curve[curveIndex] : 1
                let artBuffers: [[[Float]]] = art < articulations.count ? articulations[art] : []
                let layerBuffers: [[Float]] = layer < artBuffers.count ? artBuffers[layer] : []
                for rr in 0..<robins {
                    let source: [Float] = rr < layerBuffers.count ? layerBuffers[rr] : []
                    let samples = source.isEmpty ? [Float(0)] : source
                    let offset = packed.count
                    packed.append(contentsOf: samples)
                    var cell = LayerCell()
                    cell.offset = Int32(offset)
                    cell.count = Int32(samples.count)
                    cell.velocityHi = hi
                    cell.velocityRef = ref
                    cell.curveAtRef = atRef < 1e-8 ? 1 : atRef
                    cellPtr[cellIndex] = cell
                    cellIndex += 1
                }
            }
        }
        let storageCount = max(1, packed.count)
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: storageCount)
        if packed.isEmpty {
            storage.initialize(repeating: 0, count: 1)
        } else {
            let dest = UnsafeMutableBufferPointer(start: storage, count: packed.count)
            _ = dest.initialize(from: packed)
        }
        let curvePtr = UnsafeMutablePointer<Float>.allocate(capacity: 128)
        curvePtr.initialize(repeating: curve.last ?? 1, count: 128)
        for index in 0..<min(128, curve.count) {
            curvePtr[index] = curve[index]
        }
        return LayerBank(
            storage: storage,
            storageCount: max(1, packed.count),
            curve: curvePtr,
            cells: cellPtr,
            cellCount: cellCount,
            articulationCount: arts,
            layerCount: layers,
            roundRobin: robins,
            useCurve: useCurve ? 1 : 0
        )
    }
}
