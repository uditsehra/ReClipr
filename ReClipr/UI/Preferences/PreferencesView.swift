//
//  PreferencesView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("ignoredApps")
    private var ignoredAppsRaw: String = "com.Apple.keychainaccess"
    
    // MARK: - Duplicate handling preferences
    @AppStorage("duplicatePolicy")
    private var duplicatePolicyRaw: String = DuplicatePolicy.none.rawValue

    @AppStorage("duplicateInterval")
    private var duplicateInterval: Double = 300 // seconds (default 5 min)

    
    var body: some View {
        VStack(alignment: .leading, spacing: 12){
            Text("Preferences")
                .font(.headline)
                .padding(.bottom, 4)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10){
                Text("Duplicates")
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 6){
                    
                    duplicateOption(
                        title: "No Duplicates",
                        value: DuplicatePolicy.none
                    )
                    
                    HStack(spacing: 8){
                        duplicateOption(
                            title: "Afte Interval",
                            value: DuplicatePolicy.timed
                        )
                        
                        if duplicatePolicyRaw == DuplicatePolicy.timed.rawValue{
                            intervalPicker
                        }
                    }
                    
                    duplicateOption(
                        title: "Allow",
                        value: DuplicatePolicy.always
                    )
                }
            }
            
            Divider()
            
            HStack(spacing: 8){
                Text("Launch at Login")
                    .font(.system(size: 13, weight: .medium))
                
                Text("Start at automatically on login")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin){ _, newValue in toggleLaunchAtLogin(newValue)}
            }
            
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8){
                
                Text("Ignored Apps")
                    .font(.system(size: 13, weight: .medium))
                
                TextEditor(text: $ignoredAppsRaw)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )
                
                Text("Enter app bundle identifiers seperated by commas.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear{
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
    
    private func duplicateOption(
        title: String,
        value: DuplicatePolicy
    ) -> some View {
        HStack(spacing: 8){
            Image(systemName:
                    duplicatePolicyRaw == value.rawValue ? "largecircle.fill.circle" : "circle"
            )
            .foregroundColor(.accentColor)
            
            Text(title).font(.system(size: 13))
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            duplicatePolicyRaw = value.rawValue
        }
    }
    
    private var intervalPicker: some View {
        Menu {
            ForEach( [30, 60, 120, 300, 600, 900, 1800], id: \.self){ seconds in
                Button(label(for: seconds)){
                    duplicateInterval = Double(seconds)
                }
            }
        } label: {
            Text(label(for: Int(duplicateInterval)))
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .cornerRadius(6)
        }
    }
    
    private func label(for seconds: Int) -> String {
        seconds < 60
        ? "\(seconds)s": "\(seconds / 60)min"
    }
    
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled{
                try SMAppService.mainApp.register()
            }else {
                try SMAppService.mainApp.unregister()
            }
        } catch{
            print("Launch at login setting failed:", error)
        }
    }
}
