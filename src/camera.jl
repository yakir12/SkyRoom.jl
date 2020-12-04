mutable struct PiCam
    url::String
    cam::VideoIO.VideoReader
    buff
    encoder
    function PiCam(url::String)
        cam = VideoIO.openvideo(url)
        buff = read(cam)
        props = [:priv_data => ("crf" => "0", "preset" => "ultrafast")]
        encoder = prepareencoder(buff, framerate = 10, AVCodecContextProperties = props, codec_name = "libx264rgb")
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
