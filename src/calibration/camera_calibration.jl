function record_camera_calibration()
    picsfolder = joinpath(tempdir(), constants["calibration"]["camera"]["picsfolder"])
    if !isdir(picsfolder)
        mkdir(picsfolder)
    else
        map(rm, readdir(picsfolder, join = true))
    end

    takeapicture(joinpath(picsfolder, "img%04d.png"), options = `--keypress --fullpreview`)
end

function assemble_camera_calibration()
    datafolder = constants["calibration"]["camera"]["datafolder"]
    file = joinpath(homedir(), datafolder, "calibration_matrices.jld2")

    @load file tform itform

    M = SVector{2, Float64}.(zip(tform[:x], tform[:y]))
    _tform = interpolate(M, BSpline(Linear()))
    tform = Base.splat(extrapolate(scale(_tform, tform[:cols], tform[:rows]), Interpolations.Flat()))
    M = SVector{2, Float64}.(zip(itform[:x], itform[:y]))
    _itform = interpolate(M, BSpline(Linear()))
    itform = Base.splat(extrapolate(scale(_itform, itform[:xs], itform[:ys]), Interpolations.Flat()))

    file = joinpath(homedir(), datafolder, "calibration.jld2")
    @save file tform itform
end



function save_mask()
    mktemp() do file, _
        takeapicture(file)
        img = FileIO.load(file)
        w = constants["raspioptions"]["width"]
        h = constants["raspioptions"]["height"]
        h2 = h ÷ 2
        w2 = w ÷ 2
        m = 10
        seeds = vcat(((CartesianIndex(h2 + i, w2 + j), 1) for i in -m:m for j in -m:m)..., ((CartesianIndex(i, j), 2) for i in vcat(1:m,h-m + 1:h) for j in vcat(1:m,w-m + 1:w))...)
        segments = seeded_region_growing(img, seeds)
        mask = labels_map(segments) .== 1
        file = joinpath(homedir(), "mask.png")
        FileIO.save(file, mask)
    end
    nothing
end

function textlayer!(ax::LAxis)
    pxa = lift(AbstractPlotting.zero_origin, ax.scene.px_area)
    Scene(ax.scene, pxa, raw = true, camera = campixel!)
end
function AbstractPlotting.annotations!(textlayer::Scene, ax::LAxis, texts, positions; kwargs...)
    positions = positions isa Observable ? positions : Observable(positions)
    screenpositions = lift(positions, ax.scene.camera.projectionview, ax.scene.camera.pixel_space) do positions, pv, pspace
        p4s = to_ndim.(Vec4f0, to_ndim.(Vec3f0, positions, 0.0), 1.0)
        p1m1s = [pv *  p for p in p4s]
        projected = [inv(pspace) * p1m1 for p1m1 in p1m1s]
        pdisplay = [Point2(p[1:2]...) for p in projected]
    end
    annotations!(textlayer, texts, screenpositions; kwargs...)
end

function horizon(θ, ps)
    rm = RotMatrix(θ)
    std([last(rm*p) for p in ps])
end

function get_ends(labels, tform)
    map(1:maximum(labels)) do i
        j = findall(==(i), labels)
        xy = SVector{2, Float64}.(reverse.(Tuple.(j)))
        μ = mean(xy)
        xy .-= Ref(μ)
        o = optimize(θ -> horizon(θ, xy), -π/2, π)
        θ = -o.minimizer
        rm = RotMatrix(-θ)
        xy2 = [rm*p for p in xy]
        l = -(reverse(extrema(first, xy2))...)
        p1 = μ .+ reverse(sincos(θ)).*l./2
        p2 = μ .+ reverse(sincos(θ + π)).*l./2
        p1 = SVector{2, Float64}(tform(p1))
        p2 = SVector{2, Float64}(tform(p2))
        Δ = p2 - p1
        (length = norm(Δ), ends = p1 => p2, θ = atan(reverse(Δ)...))
    end
end

function test_camera_calibration()
    mktemp() do imgfile, _
        takeapicture(imgfile)
        img = FileIO.load(imgfile)


        maskfile = joinpath(homedir(), "mask.png")
        maskimg = FileIO.load(maskfile)
        mask = maskimg .== zero(eltype(maskimg))

        bw = Gray.(img)
        tf = bw .< otsu_threshold(bw)
        markers = label_components(tf)
        for l in unique(markers)
            i = findall(==(l), markers)
            if any(mask[i])
                markers[i] .= 0
            end
        end
        labels = replace(markers, (u => i - 1 for (i, u) in enumerate(unique(markers)))...)

        calibrationfolder = constants["calibration"]["camera"]["datafolder"]
        file = joinpath(homedir(), calibrationfolder, "calibration.jld2")
        @load file tform itform

        lxy = get_ends(labels, tform)

        indices = ImageTransformations.autorange(img, tform)
        imgw = parent(warp(img, itform, indices))

        unit = constants["calibration"]["camera"]["board"]["unit"]
        scene, layout = layoutscene(0, resolution = size(imgw))
        ax = layout[1, 1] = LAxis(scene, aspect = DataAspect(), xlabel = "X ($unit)", ylabel = "Y ($unit)")
        image!(ax, indices..., imgw)
        textlayer = textlayer!(ax)
        annotations!(textlayer, ax, [string(round(i.length, digits = 2), " ", unit) for i in lxy], [mean(i.ends) for i in lxy], color = :yellow, align = (:center, :bottom),  rotation = [i.θ for i in lxy])
        linesegments!(ax, [i.ends for i in lxy], color = :cyan)
        tightlimits!(ax)
        handler(a,b) = scene
        JSServe.Application(handler, "0.0.0.0", constants["web"]["port"])
    end
end

