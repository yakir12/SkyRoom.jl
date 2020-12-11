function ask(q)
    println(q)
    readline()
end

function onerun(setups, wind_arduinos, led_arduino, camera)
    md = Dict()
    labels = setups.label
    @label start
    l = ask("Which setup?")
    i = findfirst(==(l), labels)
    if isnothing(i)
        @info "I cannot find your choice, $l, in the available setups" labels
        @goto start
    end
    md["setup"] = label_setup(setups[i,:])
    for _ in 1:3
        update_arena!(wind_arduinos, led_arduino, setups[i,:])
    end
    ask("Press Enter to start recording")
    md["recording_time"] = string(now())
    folder = datadir / md["recording_time"]
    mkdir(folder)
    @async record(camera, wind_arduinos, folder)
    ask("Press Enter to stop recording")
    close(camera)
    md["beetle_id"]  = ask("Beetle ID")
    md["comment"] = ask("Comments")
    res = ask("Save? [Y]/n")
    if  isempty(res) || occursin(r"^y"i, res)
        open(folder / "metadata.toml", "w") do io
            TOML.print(io, md)
        end
    else
        rm(folder, force=true, recursive=true)
    end
end

function main(; setup_file = HTTP.get(setupsurl).body, fan_ports = ["/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323510141D0-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95635333930351917172-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95735353032351010260-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_55838323435351213041-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323514121D0-if00"], led_port = "/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0", cam_url = "http://130.235.245.118:8080/stream/video.mjpeg")

    wind_arduinos = [FanArduino(id, port) for (id, port) in enumerate(fan_ports) if isconnected(port)]
    led_arduino = LEDArduino(led_port)
    camera = PiCam(cam_url)

    df = CSV.File(setup_file, header = 1:2) |> DataFrame
    setups = select(df, :setup_label => identity => :label, r"fan" => ByRow(parse2wind ∘ tuple) => :fans, r"star" => ByRow(parse2stars ∘ tuple) => :stars)

    while true
        try
            onerun(setups, wind_arduinos, led_arduino, camera)
        catch ex
            res = ask("Quit? [Y]/n")
            if  isempty(res) || occursin(r"^y"i, res)
                close(camera)
                close(led_arduino)
                close.(wind_arduinos)
                throw(ex)
                return nothing
            else
                continue
            end
        end
    end
end

function record(camera, wind_arduinos, folder)
    open(camera)

    fan_io = open(folder / "fans.csv", "w")
    println(fan_io, "time,", join([join(["fan$(a.id)_speed$j" for j in 1:3], ",") for a in wind_arduinos], ","))

    tmp = folder / "temp.stream"

    open(tmp, "w") do stream_io
        i = 0
        while isopen(camera)
            i += 1

            img = get_frame(camera)
            appendencode!(camera.encoder, stream_io, img, i)

            t, rpms = get_rpms(wind_arduinos)
            println(fan_io, t, ",",join(Iterators.flatten(rpms), ","))

        end
        finishencode!(camera.encoder, stream_io)
    end
    close(fan_io)
    camera.encoder = prepareencoder(camera.buff; framerate, AVCodecContextProperties, codec_name)
end

function update_arena!(wind_arduinos, led_arduino, setup)
    for a in wind_arduinos
        a.pwm[] = setup.fans[a.id].pwm
    end
    led_arduino.msg[] = parse2arduino(setup.stars)
end

function backup()
    todo = readpath(datadir)
    n = length(todo)
    done = Vector{SystemPath}(undef, n)
    @showprogress 1 "Uploading..." for (i, folder) in enumerate(todo)
        tmp = folder / "temp.stream"
        video = folder / "track.mp4"
        mux(tmp, video, framerate, silent = true)

        tb = Tar.create(string(folder))
        source = AbstractPath(tb)
        name = basename(folder)
        destination = S3Path(bucket, name * ".tar", config = s3config)
        mv(source, destination)
        @assert AWSS3.s3_exists(s3config, "dackebeetle", name * ".tar") "upload failed for $name"
        done[i] = folder
    end
    foreach(done) do folder
        rm(folder, recursive = true)
    end
end

label_setup(x) = string("fans=", Int[i.pwm for i in x.fans], "; stars=", [string(i.cardinality, " ", i.elevation, " ", i.intensity, " ", i.radius) for i in x.stars])
