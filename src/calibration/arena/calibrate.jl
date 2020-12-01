using JLD2, Interpolations, StaticArrays, Images, FileIO, ImageFeatures, CoordinateTransformations, Rotations, ImageDraw, ColorVectorSpace, ImageCore, Clustering, ImageMorphology, LinearAlgebra, ImageFiltering, Statistics
using ImageView

function getlinelength(img, line)
    indsy, indsx = axes(img)
    cosθ = cos(line.θ)
    sinθ = sin(line.θ)
    intersections_x = [(x, (line.ρ - x*cosθ)/sinθ) for x in (first(indsx), last(indsx))]
    intersections_y = [((line.ρ - y*sinθ)/cosθ, y) for y in (first(indsy), last(indsy))]
    valid_intersections = ImageDraw.get_valid_intersections(vcat(intersections_x, intersections_y), indsx, indsy)
    data = bresenhamread(img, round(Int,valid_intersections[1][2]), round(Int,valid_intersections[1][1]), round(Int,valid_intersections[2][2]), round(Int,valid_intersections[2][1]))
    i1 = findlast(first, data) 
    i2 = findfirst(first, data)
    last(data[i1]), last(data[i2])
end



function bresenhamread(img::AbstractArray{T, 2}, y0::Int, x0::Int, y1::Int, x1::Int) where T
    data = Vector{Pair{T, Tuple{Int, Int}}}(undef, 0)
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)

    sx = x0 < x1 ? 1 : -1
    sy = y0 < y1 ? 1 : -1;

    err = (dx > dy ? dx : -dy) / 2

    while true
        push!(data, img[y0, x0] => (y0, x0))
        (x0 != x1 || y0 != y1) || break
        e2 = err
        if e2 > -dx
            err -= dy
            x0 += sx
        end
        if e2 < dy
            err += dx
            y0 += sy
        end
    end

    data
end




mount_point = "/home/yakir/mnt"

mounted = any(occursin(Regex(mount_point), l) for l in eachline("/proc/mounts"))

if !mounted
    run(`sshfs skyroom:/ $mount_point`)
end
folder = filter(startswith("jl_"), readdir(joinpath(mount_point, "tmp")))
imgfiles = readdir(joinpath(mount_point, "tmp", only(folder)), join = true)


mask = joinpath(mount_point, "home/yakir/tmp.png")
if !isfile(mask)
    run(`ssh skyroom /home/yakir/SkyRoom.jl/calibration/arena/mask.sh`)
end
bw = Gray.(FileIO.load(mask))
th = otsu_threshold(bw)
mask = findall(erode(opening(bw .< th)))




imgfile = imgfiles[3]

function main(imgfile)

    bw = Gray.(FileIO.load(imgfile))
    bw[mask] .= NaN

    bkg = imfilter(bw, Kernel.gaussian(20))
    bw = bw .- bkg
    bw[mask] .= Gray(0.0)

    for i in mask
        bw[i] = Gray(0.0)
    end

    th = otsu_threshold(bw)
    tf = opening(bw .< th)
    lb = label_components(tf)

    w, h = size(tf)
    for i in (1, w), j in (1, h)
        l = lb[j, i]
        lb[lb .== l] .= 0
    end

    tf = lb .!= 0

    t = thinning(tf)

    rθ = hough_transform_standard(t, stepsize = 1, vote_threshold = 10, max_linecount = 100, angles = range(0, pi, length = 10000))

    R = kmeans(Matrix(hcat(vcat.(rθ...)...)'),1)
    M = R.centers 
    m = [(; ρ, θ) for (ρ, θ) in eachcol(M)]

    ps = map(m) do line
        getlinelength(tf, line)
    end
    ps

end

