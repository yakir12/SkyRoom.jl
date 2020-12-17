mutable struct PiCamera
    cam::PyObject
    framerate::Int
    resolution::Tuple{Int, Int}
    resize::Tuple{Int, Int}
    function PiCamera(framerate::Int, W::Int, H::Int, r::Int)
        cam = py"PC"()
        resolution = (16W, 16H)
        cam.resolution = resolution
        cam.framerate = framerate
        resize = resolution .÷ r
        new(cam, framerate, resolution, resize)
    end
end

Base.isopen(a::PiCamera) = !a.cam.closed
Base.close(a::PiCamera) = isopen(a) && a.cam.close()
function Base.open(a::PiCamera) 
    close(a)
    cam = py"PC"()
    cam.resolution = a.resolution
    cam.framerate = a.framerate
    a.cam = cam
end
restart(a::PiCamera) = (close(a); open(a))

function snap(camera::PiCamera)
    stream = py"PIO"()
    camera.cam.capture(stream, splitter_port = 0, resize = camera.resize, format = "jpeg", use_video_port = true)
    stream.seek(0)
    buffer = IOBuffer(stream.read())
    load(buffer)
end

