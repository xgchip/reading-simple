import AppKit
import Foundation
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func render(_ size:Int)->Data {
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep);let scale=CGFloat(size)/1024
 NSGraphicsContext.current!.imageInterpolation = .high
 let transform=NSAffineTransform();transform.scale(by:scale);transform.concat()
 NSColor(calibratedRed:0.25,green:0.36,blue:0.29,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:60,y:60,width:904,height:904),xRadius:200,yRadius:200).fill()
 let paper=NSColor(calibratedRed:0.98,green:0.97,blue:0.92,alpha:1);paper.setFill()
 let left=NSBezierPath();left.move(to:NSPoint(x:200,y:300));left.line(to:NSPoint(x:200,y:755));left.curve(to:NSPoint(x:500,y:720),controlPoint1:NSPoint(x:330,y:800),controlPoint2:NSPoint(x:400,y:780));left.line(to:NSPoint(x:500,y:260));left.curve(to:NSPoint(x:200,y:300),controlPoint1:NSPoint(x:370,y:330),controlPoint2:NSPoint(x:300,y:345));left.fill()
 let right=NSBezierPath();right.move(to:NSPoint(x:524,y:260));right.line(to:NSPoint(x:524,y:720));right.curve(to:NSPoint(x:824,y:755),controlPoint1:NSPoint(x:630,y:780),controlPoint2:NSPoint(x:735,y:800));right.line(to:NSPoint(x:824,y:300));right.curve(to:NSPoint(x:524,y:260),controlPoint1:NSPoint(x:710,y:345),controlPoint2:NSPoint(x:640,y:330));right.fill()
 NSColor(calibratedRed:0.79,green:0.83,blue:0.52,alpha:1).setFill();NSBezierPath(roundedRect:NSRect(x:582,y:495,width:180,height:28),xRadius:7,yRadius:7).fill()
 for (y,width) in [(640.0,155.0),(580,155),(435,115)] {NSColor(calibratedRed:0.48,green:0.56,blue:0.43,alpha:0.55).setFill();NSBezierPath(roundedRect:NSRect(x:582,y:y,width:width,height:10),xRadius:5,yRadius:5).fill()}
 NSGraphicsContext.restoreGraphicsState();return rep.representation(using:.png,properties:[:])!
}
for size in [16,32,128,256,512] {try render(size).write(to:directory.appendingPathComponent("icon_\(size)x\(size).png"));try render(size*2).write(to:directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))}
