//
//  ContentView.swift
//  ShadowExp
//
//  Created by HungNT on 8/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Current Screen: Main View")
                
                // 2. NavigationLink pushes the DetailView onto the stack
                NavigationLink("Go to Detail Screen") {
                    ARScreen()
                }
            }
            .navigationTitle("Main")
        }
    }
}
