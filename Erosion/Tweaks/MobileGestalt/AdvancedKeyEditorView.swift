import SwiftUI

struct AdvancedKeyEditorView: View {
    private let gestaltURL = MGURL.fsGestaltURL

    @State private var plist: [String: Any] = [:]
    @State private var search = ""
    @State private var selectedSection = "CacheExtra"
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isLoading = false

    private var entries: [(key: String, value: Any)] {
        guard let dict = plist[selectedSection] as? [String: Any] else { return [] }
        return dict
            .filter { search.isEmpty || $0.key.localizedCaseInsensitiveContains(search) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        List {
            Section {
                Picker("Dictionary", selection: $selectedSection) {
                    Text("CacheExtra").tag("CacheExtra")
                    Text("CacheData").tag("CacheData")
                }
                .pickerStyle(.menu)

                TextField("Search keys", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                HeaderLabel("MobileGestalt", symbol: "list.bullet.rectangle")
            }

            if selectedSection == "CacheData" {
                Section {
                    CacheDataViewer(value: plist["CacheData"], valueDescription: valueDescription)
                } header: {
                    HeaderLabel("CacheData", symbol: "doc.text.magnifyingglass")
                }
            } else {
                Section {
                    if entries.isEmpty {
                        ContentUnavailableView("No Keys", systemImage: "magnifyingglass", description: Text("No editable entries were found."))
                    } else {
                        ForEach(entries, id: \.key) { item in
                            NavigationLink {
                                AdvancedKeyValueEditor(
                                    section: selectedSection,
                                    key: item.key,
                                    value: item.value,
                                    onSave: { newValue in
                                        saveValue(newValue, forKey: item.key, in: selectedSection)
                                    }
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.key)
                                        .font(.system(.body, design: .monospaced))
                                    Text(valueDescription(item.value))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                } header: {
                    HeaderLabel(selectedSection, symbol: "key")
                }
            }
        }
        .navigationTitle("Advanced Key Editor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Reload") { load() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { saveCurrentPlist() }
                    .disabled(plist.isEmpty)
            }
        }
        .onAppear { load() }
        .alert("MobileGestalt", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func ensureWriteAccess() throws {
        if !FileManager.default.isWritableFile(atPath: gestaltURL.path) {
            let result = BadQuery().grantAccess(
                atPath: gestaltURL.deletingLastPathComponent().path,
                toFileName: gestaltURL.lastPathComponent
            )
            guard result.0 else {
                throw "Could not obtain write access to the MobileGestalt cache."
            }
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            try ensureWriteAccess()
            let data = try Data(contentsOf: gestaltURL)
            guard let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                throw "MobileGestalt is not a dictionary plist."
            }
            plist = object
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // Writes the exact edited dictionary immediately. The old implementation only
    // changed the parent's @State from the child editor; tapping the child's Save
    // therefore dismissed the editor but never persisted the new value to disk.
    private func saveValue(_ value: Any, forKey key: String, in section: String) {
        var updated = plist
        var sectionDict = updated[section] as? [String: Any] ?? [:]
        sectionDict[key] = value
        updated[section] = sectionDict

        do {
            try writeAndVerify(updated)
            plist = updated
            Haptic.shared.play(.soft)
            Alertinator.shared.alert(
                title: "MobileGestalt Saved",
                body: "\(key) was written and verified on disk."
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func saveCurrentPlist() {
        do {
            guard !plist.isEmpty else { throw "MobileGestalt is empty." }
            try writeAndVerify(plist)
            Haptic.shared.play(.soft)
            Alertinator.shared.alert(
                title: "MobileGestalt Saved",
                body: "The edited MobileGestalt cache was written and verified on disk."
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func writeAndVerify(_ dictionary: [String: Any]) throws {
        try ensureWriteAccess()

        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .binary,
            options: 0
        )

        // Reuse Erosion's known-working MobileGestalt write implementation.
        guard mgWrite(data) else {
            throw "MobileGestalt write failed. Check the Erosion log for the write error."
        }

        let written = try Data(contentsOf: gestaltURL)
        guard written == data else {
            throw "MobileGestalt write was not visible on disk after the write."
        }

        guard let verified = try PropertyListSerialization.propertyList(
            from: written,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw "MobileGestalt could not be read back after saving."
        }

        // Verify the edited section/key specifically, not just the byte stream.
        for (section, object) in dictionary {
            guard let expectedSection = object as? [String: Any],
                  let actualSection = verified[section] as? [String: Any] else { continue }
            for (key, expectedValue) in expectedSection {
                guard let actualValue = actualSection[key] else {
                    throw "Verification failed: \(section).\(key) is missing after the write."
                }
                if !propertyListValuesEqual(expectedValue, actualValue) {
                    throw "Verification failed: \(section).\(key) did not retain the new value."
                }
            }
        }
    }

    private func propertyListValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let a = lhs as? String, let b = rhs as? String { return a == b }
        if let a = lhs as? NSNumber, let b = rhs as? NSNumber {
            if CFGetTypeID(a) == CFBooleanGetTypeID() || CFGetTypeID(b) == CFBooleanGetTypeID() {
                return a.boolValue == b.boolValue
            }
            return a == b
        }
        if let a = lhs as? Data, let b = rhs as? Data { return a == b }
        if let a = lhs as? [String: Any], let b = rhs as? [String: Any] {
            guard a.count == b.count else { return false }
            for (key, value) in a {
                guard let other = b[key], propertyListValuesEqual(value, other) else { return false }
            }
            return true
        }
        if let a = lhs as? [Any], let b = rhs as? [Any] {
            return a.count == b.count && zip(a, b).allSatisfy { propertyListValuesEqual($0, $1) }
        }
        return String(describing: lhs) == String(describing: rhs)
    }

    private func valueDescription(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let data = value as? Data { return "Data (\(data.count) bytes)" }
        if let dict = value as? [String: Any] { return "Dictionary (\(dict.count) keys)" }
        if let array = value as? [Any] { return "Array (\(array.count) items)" }
        return String(describing: value)
    }
}

private struct CacheDataViewer: View {
    let value: Any?
    let valueDescription: (Any) -> String

    var body: some View {
        Group {
            if let value {
                CacheDataNode(value: value, label: "CacheData", valueDescription: valueDescription)
            } else {
                ContentUnavailableView("CacheData Empty", systemImage: "doc.text", description: Text("CacheData is not present in this MobileGestalt cache."))
            }
        }
    }
}

private struct CacheDataNode: View {
    let value: Any
    let label: String
    let valueDescription: (Any) -> String

    var body: some View {
        if let dict = value as? [String: Any] {
            if dict.isEmpty {
                LabeledContent(label, value: "Empty dictionary")
            } else {
                DisclosureGroup {
                    ForEach(dict.keys.sorted(), id: \.self) { key in
                        if let child = dict[key] {
                            CacheDataNode(value: child, label: key, valueDescription: valueDescription)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.system(.body, design: .monospaced))
                        Text("Dictionary (\(dict.count) keys)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if let array = value as? [Any] {
            DisclosureGroup {
                ForEach(Array(array.enumerated()), id: \.offset) { index, child in
                    CacheDataNode(value: child, label: "[\(index)]", valueDescription: valueDescription)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(.body, design: .monospaced))
                    Text("Array (\(array.count) items)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let data = value as? Data {
            NavigationLink {
                CacheDataHexView(title: label, data: data)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(.body, design: .monospaced))
                    Text("Data (\(data.count) bytes) — tap to view hex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent {
                Text(valueDescription(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(label).font(.system(.body, design: .monospaced))
            }
        }
    }
}

private struct CacheDataHexView: View {
    let title: String
    let data: Data

    private var hex: String {
        data.map { String(format: "%02X", $0) }.chunked(into: 16).map { $0.joined(separator: " ") }.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            Text(hex.isEmpty ? "<empty>" : hex)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}

private struct AdvancedKeyValueEditor: View {
    let section: String
    let key: String
    let value: Any
    let onSave: (Any) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var textValue = ""
    @State private var type = "String"

    var body: some View {
        Form {
            Section {
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                HeaderLabel(section, symbol: "key")
            }

            Section {
                Picker("Type", selection: $type) {
                    Text("String").tag("String")
                    Text("Integer").tag("Integer")
                    Text("Boolean").tag("Boolean")
                }

                if type == "Boolean" {
                    Toggle("Value", isOn: Binding(
                        get: { textValue == "true" },
                        set: { textValue = $0 ? "true" : "false" }
                    ))
                } else {
                    TextField("Value", text: $textValue, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
        .navigationTitle("Edit Value")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    guard let converted = convertedValue() else { return }
                    onSave(converted)
                    dismiss()
                }
            }
        }
        .onAppear {
            switch value {
            case let string as String:
                type = "String"
                textValue = string
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    type = "Boolean"
                    textValue = number.boolValue ? "true" : "false"
                } else {
                    type = "Integer"
                    textValue = number.stringValue
                }
            default:
                type = "String"
                textValue = String(describing: value)
            }
        }
    }

    private func convertedValue() -> Any? {
        switch type {
        case "Integer": return Int(textValue.trimmingCharacters(in: .whitespacesAndNewlines))
        case "Boolean": return textValue == "true"
        default: return textValue
        }
    }
}
