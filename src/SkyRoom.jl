module SkyRoom

export main

using FilePathsBase
using FilePathsBase: /
using AWSS3

const bucket = "s3://dackebeetle"
tmp = S3Path(bucket)
tmp.config.region = "eu-north-1"
s3config = tmp.config

const baudrate = 9600

const datadir = home() / "data"
isdir(datadir) || mkpath(datadir)

# Fans
const t4 = 15000000
const top_rpm = 12650
const shortest_t = t4/1.1top_rpm

# LED 
const strips = 2
const ledsperstrip = 150
const brightness = 1
const deadleds = 9
const cardinals = ["NE", "SW", "SE", "NW"]
const liveleds = ledsperstrip - deadleds

# camera
const framerate = 25
const AVCodecContextProperties = [:priv_data => ("crf" => "0", "preset" => "ultrafast")]
const codec_name = "libx264rgb"

# experiments
const setupsurl = "https://docs.google.com/spreadsheets/d/e/2PACX-1vQNLWhLfp_iuW68j7SM6Px8ysTmbrfmrP_7ipXK9BkfzBgfqn3Mj7ra177mZyHlY5NLA3SDtfYNTROv/pub?gid=0&single=true&output=csv"

include("cobs.jl")

using LibSerialPort
include("abstractarduinos.jl")

using Observables
include("leds.jl")

using Dates
include("winds.jl")

using Colors
using FixedPointNumbers
using VideoIO
include("camera.jl")

# import ProgressMeter
# using ProgressMeter: @showprogress
# using GLMakie
# using AbstractPlotting
# using AbstractPlotting.MakieLayout
# using DataStructures
# using CSV, DataFrames
# using HTTP
# using Tar
# include("main.jl")

import ProgressMeter
using ProgressMeter: @showprogress
using DataStructures
using CSV, DataFrames
using HTTP
using Tar
import Pkg.TOML
include("simpler.jl")

end # module

# AWSS3 AbstractPlotting CSV Colors DataFrames DataStructures FilePathsBase FixedPointNumbers GLMakie HTTP LibSerialPort Observables VideoIO Dates
