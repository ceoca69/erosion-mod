//
//  FMRootView.swift
//  Erosion
//
//  Created by lunginspector on 8/26/26.
//

import SwiftUI

enum FSPaths {
    static let appContainers = "/var/mobile/Containers/Data/Application"
    static var appBundles = "/var/containers/Bundle/Application"
}

enum FSURL {
    static let appContainers = URL(fileURLWithPath: FSPaths.appContainers)
    static var sysGroup = URL(fileURLWithPath: "/var/containers/Shared/SystemGroup")
    static var configProfiles = FSURL.sysGroup.appendingPathComponent("systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles")
    static var internalDaemons = URL(fileURLWithPath: "/var/mobile/Containers/Data/InternalDaemon")
    static var appPlugins = URL(fileURLWithPath: "/var/mobile/Containers/Data/PluginKitPlugin")
    static var appGroup = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup")
    static var systemData = URL(fileURLWithPath: "/var/containers/Data/System")
    static let systemLibrary = URL(fileURLWithPath: "/System/Library")
    static let systemDeveloper = URL(fileURLWithPath: "/System/Developer")
    static let systemCryptexes = URL(fileURLWithPath: "/System/Cryptexes")
}

struct FMRootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Data Containers", destination: FileBrowserView(path: FSURL.appContainers, isContainer: true))
                    NavigationLink("Plugin Containers", destination: FileBrowserView(path: FSURL.appPlugins, isContainer: true))
                    NavigationLink("App Groups", destination: FileBrowserView(path: FSURL.appGroup, shouldGrant: true))
                } header: {
                    HeaderLabel("Apps", symbol: "square.grid.2x2")
                }
                
                Section {
                    NavigationLink("Daemon Containers", destination: FileBrowserView(path: FSURL.internalDaemons, isContainer: true))
                    NavigationLink("System Containers", destination: FileBrowserView(path: FSURL.systemData, shouldGrant: true))
                    NavigationLink("SystemGroup Containers", destination: FileBrowserView(path: FSURL.sysGroup, isContainer: true))
                } header: {
                    HeaderLabel("System", symbol: "gear")
                }

                Section {
                    NavigationLink("Library", destination: FileBrowserView(path: FSURL.systemLibrary, readOnly: true))
                    NavigationLink("Developer", destination: FileBrowserView(path: FSURL.systemDeveloper, readOnly: true))
                    NavigationLink("Cryptexes", destination: FileBrowserView(path: FSURL.systemCryptexes, readOnly: true))
                } header: {
                    HeaderLabel("System Paths", symbol: "folder.badge.gearshape")
                } footer: {
                    Text("System paths are displayed read-only. File modifications are disabled.")
                }
            }
            .navigationTitle("File Browser")
        }
    }
}
