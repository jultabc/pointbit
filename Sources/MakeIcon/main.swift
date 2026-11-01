// Writes the app icon PNGs into an .iconset folder for iconutil. Usage: MakeIcon <iconset dir>
import PointbitKit
try AppIcon.writeIconset(to: CommandLine.arguments[1])
