module SkyRoom

export main

using PyCall, Dates, WGLMakie, AbstractPlotting, JSServe, ImageCore, FilePathsBase, CSV, DataFrames, HTTP, Pkg.TOML, Tar, FileIO, ImageMagick, LibSerialPort, Observables
using FilePathsBase: /
using JSServe.DOM
using JSServe: @js_str

# picamera = pyimport("picamera")
# io =  pyimport("io")

function __init__()
    py"""
    import picamera
    import io

    def PC():
        return picamera.PiCamera()

    def PIO():
        return io.BytesIO()
    """

end

const datadir = p"/home/pi/mnt/data"
isdir(datadir) || mkpath(datadir)

# Fans
const baudrate = 9600
const t4 = 15000000
const top_rpm = 12650
const shortest_t = t4/1.1top_rpm
const fan_ports = ["/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323510141D0-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95635333930351917172-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95735353032351010260-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_55838323435351213041-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323514121D0-if00"]

# LED 
const strips = 2
const ledsperstrip = 150
const brightness = 1
const deadleds = 9
const cardinals = ["NE", "SW", "SE", "NW"]
const liveleds = ledsperstrip - deadleds
const led_port = Dict("skyroom" => "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_757353036313519070B1-if00", "skyroom2" => "/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0")

const setupsurl = Dict("skyroom" => "https://docs.google.com/spreadsheets/d/e/2PACX-1vQNLWhLfp_iuW68j7SM6Px8ysTmbrfmrP_7ipXK9BkfzBgfqn3Mj7ra177mZyHlY5NLA3SDtfYNTROv/pub?gid=0&single=true&output=csv", "skyroom2" => "https://docs.google.com/spreadsheets/d/e/2PACX-1vSfv92ymTJjwdU-ft9dgglOOnxPVWwtk6gFIVSocHM3jSfHkjYk-mtEXl3g96-735Atbk1LBRt-8lAY/pub?gid=0&single=true&output=csv")
const port = 8082

include("cobs.jl")
include("abstractarduinos.jl")
include("leds.jl")
include("winds.jl")
include("camera.jl")
include("main.jl")

end # module

# PyCall, Dates, WGLMakie, AbstractPlotting, JSServe, ImageCore, FilePathsBase, CSV, DataFrames, HTTP, Pkg.TOML, Tar, FileIO, ImageMagick, LibSerialPort, Observables
