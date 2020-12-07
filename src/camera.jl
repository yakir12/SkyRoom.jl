mutable struct PiCam
    url::String
    cam::VideoIO.VideoReader
    buff
    encoder
    function PiCam(url::String)
        cam = VideoIO.openvideo(url)
        buff = read(cam)
        encoder = prepareencoder(buff; framerate, AVCodecContextProperties, codec_name)
        new(url, cam, buff, encoder)
    end
end

get_frame(c) = read!(c.cam, c.buff)

Base.isopen(c::PiCam) = isopen(c.cam)
Base.close(c::PiCam) = isopen(c) && close(c.cam)
function Base.open(c::PiCam) 
    if !isopen(c) 
        c.cam = VideoIO.openvideo(c.url)
    end
end
restart(c::PiCam) = (close(c); open(c))
