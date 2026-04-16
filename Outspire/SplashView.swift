import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5

    var body: some View {
        if isActive {
            // Replace with your actual Main ContentView
            ContentView() 
        } else {
            VStack {
                VStack(spacing: 20) {
                    // Replace "sparkles" with your Outspire logo asset
                    Image(systemName: "sparkles") 
                        .font(.system(size: 80))
                        .foregroundColor(.blue) // Use your primary brand color
                    
                    Text("Outspire")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.0)) {
                        self.size = 1.0
                        self.opacity = 1.0
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
            .onAppear {
                // Simulates loading time before transitioning to the main app
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}
