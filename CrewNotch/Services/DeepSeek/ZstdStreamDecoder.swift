//
//  ZstdStreamDecoder.swift
//  CrewNotch
//
//  Incremental zstd decompression: feed bytes as a file grows, get the
//  decompressed bytes back. Handles frames split across reads.
//

import Foundation
import libzstd

nonisolated final class ZstdStreamDecoder {
    private let stream: OpaquePointer
    private var output = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())

    init?() {
        guard let stream = ZSTD_createDStream() else { return nil }
        self.stream = stream
        ZSTD_initDStream(stream)
    }

    deinit {
        ZSTD_freeDStream(stream)
    }

    /// Decompresses `data`, keeping any incomplete frame buffered for the next call.
    /// Returns nil if the input is corrupt.
    func decode(_ data: Data) -> Data? {
        var result = Data()
        let failed: Bool = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var input = ZSTD_inBuffer(src: base, size: raw.count, pos: 0)
            while true {
                let (code, written): (Int, Int) = output.withUnsafeMutableBytes { out in
                    var buffer = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    let code = ZSTD_decompressStream(stream, &buffer, &input)
                    return (code, buffer.pos)
                }
                if ZSTD_isError(code) != 0 { return true }
                result.append(contentsOf: output[0..<written])
                // Done once all input is consumed and the output buffer wasn't filled.
                if input.pos == input.size && written < output.count { return false }
            }
        }
        if failed {
            ZSTD_initDStream(stream)
            return nil
        }
        return result
    }
}
