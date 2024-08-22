///*
//See LICENSE folder for this sample’s licensing information.
//
//Abstract:
//A view that shows the depth image on top of the color image with a slider
// to adjust the depth layer's opacity.
//*/
//
//import SwiftUI
//
//struct DepthOverlay: View {
//    
//    @ObservedObject var manager: CameraManager
//    @State var exposureValue = Float(0.5)
//    @State var minDepthSlider = Float(0.5)
//    @State private var opacity = Float(0.5)
//    @Binding var maxDepth: Float
//    @Binding var minDepth: Float
//    @Binding var redSaturation: Float
//    @Binding var greenSaturation: Float
//    @Binding var blueSaturation: Float
//    @Binding var isBackgroundControlOn: Bool
//    
//    var body: some View {
//        if manager.dataAvailable {
//            VStack {
//                //SliderDepthBoundaryView(val: $opacity, label: "Opacity", minVal: 0, maxVal: 1)
//                ZStack {
//                    MetalTextureViewColor(
//                        rotationAngle: rotationAngle,
//                        capturedData: manager.capturedData,
//                        exposureValue: $exposureValue, // Added by Jessica Kinnevan
//                        minDepthSlider: $minDepthSlider, // Added by Jessica Kinnevan
//                        redSaturation: $redSaturation,
//                        greenSaturation: $greenSaturation,
//                        blueSaturation: $blueSaturation,
//                        isBackgroundControlOn: $isBackgroundControlOn
//                    )
//                    MetalTextureDepthView(
//                        rotationAngle: rotationAngle,
//                        maxDepth: $maxDepth,
//                        minDepth: $minDepth,
//                        capturedData: manager.capturedData
//                    )
//                        .opacity(Double(opacity))
//                }
//            }
//        }
//    }
//}
