import Foundation
import Testing
@testable import HQKit

@Test func skinTonesComeInThreeEvenGroups() {
    let skins = FacePalette.skins
    #expect(skins.count == 9)
    #expect(zip(skins, skins.dropFirst()).allSatisfy { $0.lightness > $1.lightness }, "light to deep")
    for (index, skin) in skins.enumerated() {
        switch FacePalette.group(ofSkin: index) {
        case .light: #expect(skin.lightness >= 75, "tone \(index + 1) is light")
        case .medium: #expect((56..<74).contains(skin.lightness), "tone \(index + 1) is medium, not dark")
        case .deep: #expect(skin.lightness < 46, "tone \(index + 1) is deep")
        }
    }
    #expect(FacePalette.SkinGroup.allCases.allSatisfy { group in skins.indices.filter { FacePalette.group(ofSkin: $0) == group }.count == 3 })
}

@Test func aNewFaceTakesAToneAndGroupTheOpenSessionsLack() {
    let deep = (0..<200).compactMap { index -> FaceSpec? in
        let face = FaceSpec(id: "deep-\(index)")
        return FacePalette.group(ofSkin: face.skin) == .deep ? face : nil
    }
    let open = Array(deep.prefix(3))
    for index in 0..<300 {
        let id = "new-\(index)"
        let face = FaceSpec(id: id, salt: FaceSpec.salt(for: id, among: open))
        #expect(FacePalette.group(ofSkin: face.skin) != .deep && !open.map(\.skin).contains(face.skin))
        #expect(!open.map(\.signature).contains(face.signature))
    }
}

/// Six sessions opened one by one: every group shows and no tone repeats; two of each group but when 16 tries can't.
@Test func sixSessionsOpenedOneByOneShowEveryGroup() {
    var even = 0
    for run in 0..<100 {
        var open: [FaceSpec] = []
        for index in 0..<6 {
            let id = "run-\(run)-\(index)"
            open.append(FaceSpec(id: id, salt: FaceSpec.salt(for: id, among: open)))
        }
        let groups = Dictionary(grouping: open) { FacePalette.group(ofSkin: $0.skin) }.mapValues(\.count)
        #expect(groups.count == 3, "run \(run): \(groups)")
        #expect(Set(open.map(\.skin)).count == 6 && Set(open.map(\.signature)).count == 6)
        if FacePalette.SkinGroup.allCases.allSatisfy({ groups[$0] == 2 }) { even += 1 }
    }
    #expect(even >= 90, "\(even) of 100 runs two of each")
}
