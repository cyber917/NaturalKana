import Foundation
import Testing
import NaturalKanaStorage

@Test func signedGroupMetadataIsAuthoritative() throws {
    let base = "group.org.naturalkana"
    #expect(try SharedContainer.identifier(info: ["NaturalKanaAppGroup": base]) == base)
    #expect(try SharedContainer.identifier(info: ["NaturalKanaAppGroup": base, "ALTAppGroups": [base + ".EXAMPLE", "group.other"]]) == base + ".EXAMPLE")
    #expect(throws: SharingFailure.groupAmbiguous) {
        try SharedContainer.identifier(info: ["NaturalKanaAppGroup": base, "ALTAppGroups": []])
    }
    #expect(throws: SharingFailure.groupAmbiguous) {
        try SharedContainer.identifier(info: ["NaturalKanaAppGroup": base, "ALTAppGroups": [base, base + ".EXAMPLE"]])
    }
    #expect(throws: SharingFailure.groupAmbiguous) {
        try SharedContainer.identifier(info: ["NaturalKanaAppGroup": base, "ALTAppGroups": [base + "fake.EXAMPLE"]])
    }
    #expect(throws: SharingFailure.groupMetadata) { try SharedContainer.identifier(info: [:]) }
}

@Test func keychainRequiresActualPrefixAndExpectedSharedSuffix() {
    #expect(SharedKeychain.matches(group: "OLDPREFIX.org.naturalkana", suffix: "org.naturalkana"))
    #expect(!SharedKeychain.matches(group: "org.naturalkana", suffix: "org.naturalkana"))
    #expect(!SharedKeychain.matches(group: "$(AppIdentifierPrefix)org.naturalkana", suffix: "org.naturalkana"))
    #expect(!SharedKeychain.matches(group: "PREFIX.org.naturalkana.keyboard", suffix: "org.naturalkana"))
    #expect(!SharedKeychain.matches(group: "PREFIX.other.org.naturalkana", suffix: "org.naturalkana"))
}
