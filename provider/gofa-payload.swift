import Foundation

// Reflect only the measured GOFA value types. No private Swift calling convention or offsets.
private func unwrap(_ input: Any) -> Any? {
    var value = input
    for _ in 0..<4 {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle != .optional { return value }
        guard let first = mirror.children.first else { return nil }
        value = first.value
    }
    return nil
}
private func field(_ value: Any, _ name: String) -> Any? {
    guard let child = Mirror(reflecting: value).children.first(where: { $0.label == name }) else { return nil }
    return unwrap(child.value)
}
private func integer(_ value: Any?) -> Int? { value as? Int }

@_cdecl("GVMGofaPayload")
public func gofaPayload(_ pointer: UnsafeRawPointer) -> UnsafeMutableRawPointer? {
    let note = Unmanaged<NSNotification>.fromOpaque(pointer).takeUnretainedValue()
    let info = note.userInfo ?? [:]
    var result: [String: Any] = [:]
    if note.name.rawValue == "notificationSpeedBoard" {
        guard let raw = info["pushSpeedBoard"] else { return nil }
        if let model = unwrap(raw) {
            guard String(reflecting: type(of: model)) == "GOFA.SpeedBoardModel" else { return nil }
            result["speedLimit"] = integer(field(model, "currentAllowSpeed")) ?? NSNull() as Any
            result["speed"] = integer(field(model, "userSpeed")) ?? NSNull() as Any
        } else {
            // An empty native board clears the limit instead of leaving the previous one.
            result["speedLimit"] = NSNull()
        }
    } else if note.name.rawValue == "notificationNextBoard" || note.name.rawValue == "notificationOtherBoard" {
        let key = note.name.rawValue == "notificationNextBoard" ? "pushNextBoard" : "pushOtherBoardToCarplay"
        guard let raw = info[key], let value = unwrap(raw),
              String(reflecting: type(of: value)) == "Swift.Array<GOFA.DatapointModel>" else { return nil }
        var candidates: [[String: Any]] = []
        for child in Mirror(reflecting: value).children.prefix(64) {
            let point = child.value
            guard String(reflecting: type(of: point)) == "GOFA.DatapointModel",
                  let identity = integer(field(point, "id")), let sign = integer(field(point, "traffic_sign_id")),
                  let latitude = field(point, "lat") as? Double, let longitude = field(point, "lon") as? Double,
                  latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { continue }
            // Coordinates stay inside the source process, solely for native distanceFromLocation.
            candidates.append(["identity": identity, "sign": sign, "latitude": latitude, "longitude": longitude])
        }
        result["candidates"] = candidates
        result["candidateGroup"] = note.name.rawValue
    } else if note.name.rawValue == "notificationLaneBoards" {
        // GOFA posts its lane board ahead about once a second, or none; one it cannot describe is none.
        guard let raw = info["pushLaneBoardsValue"] else { return nil }
        result["laneBoard"] = unwrap(raw).flatMap(laneBoard) ?? NSNull()
    } else { return nil }
    return Unmanaged.passRetained(result as NSDictionary).toOpaque()
}
// The lanes of a GOFA lane board (`metadata.detail_lanes`) and where it stands. Coordinates stay in
// the source process, solely for native distanceFromLocation.
private func laneBoard(_ point: Any) -> [String: Any]? {
    guard String(reflecting: type(of: point)) == "GOFA.DatapointModel",
          let identity = integer(field(point, "id")),
          let latitude = field(point, "lat") as? Double, let longitude = field(point, "lon") as? Double,
          latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180,
          let metadata = field(point, "metadata"), let lanes = field(metadata, "detail_lanes") as? String,
          !lanes.isEmpty, lanes.utf8.count <= 256 else { return nil }
    return ["identity": identity, "lanes": lanes, "latitude": latitude, "longitude": longitude]
}
