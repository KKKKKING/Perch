import Foundation
import CryptoKit

/// Produces the `x-client-transaction-id` header X expects on its GraphQL endpoints.
/// Swift port of Flare's `ElonMusk1145141919810.senpaiSukissu`: fetches a dictionary of
/// `(animationKey, verification)` pairs once, then signs each `(method, path)` with SHA256
/// plus a one-byte XOR cipher. Best-effort — `id` returns nil if the dictionary can't be
/// loaded, and callers simply omit the header rather than blocking the request.
actor TwitterTransactionID {
    static let shared = TwitterTransactionID()

    private struct Pair: Decodable {
        let animationKey: String
        let verification: String
    }

    private var pairs: [Pair]?
    private var fetchFailed = false

    private static let dictURL = "https://raw.githubusercontent.com/fa0311/x-client-transaction-id-pair-dict/refs/heads/main/pair.json"
    private static let keyword = "obfiowerehiring"
    private static let additionRandom: UInt8 = 3
    private static let epochOffsetMillis: Double = 1_682_924_400 * 1000

    /// Signed transaction id for a request, or nil when the pair dictionary is unavailable.
    func id(method: String, path: String) async -> String? {
        guard let pairs = await loadPairs(),
              let pair = pairs.randomElement(),
              let keyBytes = Data(base64Encoded: pair.verification) else { return nil }

        let timeNow = Int((Date().timeIntervalSince1970 * 1000 - Self.epochOffsetMillis) / 1000)
        let timeBytes: [UInt8] = [
            UInt8(timeNow & 0xff),
            UInt8((timeNow >> 8) & 0xff),
            UInt8((timeNow >> 16) & 0xff),
            UInt8((timeNow >> 24) & 0xff),
        ]
        let data = "\(method)!\(path)!\(timeNow)\(Self.keyword)\(pair.animationKey)"
        let hashPrefix = Array(SHA256.hash(data: Data(data.utf8)).prefix(16))

        var payload = [UInt8](keyBytes)
        payload.append(contentsOf: timeBytes)
        payload.append(contentsOf: hashPrefix)
        payload.append(Self.additionRandom)

        let randomByte = UInt8.random(in: 0...255)
        var out: [UInt8] = [randomByte]
        out.append(contentsOf: payload.map { $0 ^ randomByte })
        return Data(out).base64EncodedString()
    }

    private func loadPairs() async -> [Pair]? {
        if let pairs { return pairs }
        if fetchFailed { return nil }
        guard let url = URL(string: Self.dictURL) else { fetchFailed = true; return nil }
        let started = Date()
        guard let (data, resp) = try? await URLSession.shared.data(from: url) else {
            NetworkLog.shared.log(method: "GET", url: url, status: nil, bytes: 0,
                                  startedAt: started, detail: "transport error")
            fetchFailed = true
            return nil
        }
        let code = (resp as? HTTPURLResponse)?.statusCode
        NetworkLog.shared.log(method: "GET", url: url, status: code, bytes: data.count, startedAt: started)
        guard code == 200,
              let decoded = try? JSONDecoder().decode([Pair].self, from: data),
              !decoded.isEmpty else {
            fetchFailed = true
            return nil
        }
        pairs = decoded
        return decoded
    }
}
