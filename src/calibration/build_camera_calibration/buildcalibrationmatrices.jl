using CameraCalibrations, JLD2
import Pkg.TOML

constfile = joinpath(dirname(Base.find_package("SkyRoom")), "..", "constants.toml")
constants = TOML.parsefile(constfile)

picsfolder = constants["calibration"]["camera"]["picsfolder"]

mount_point = "/home/yakir/mnt"
if !ismount(mount_point)
    run(`sshfs skyroom:/ $mount_point`)
end

calibration_images = joinpath(mount_point, "tmp", picsfolder)
check = constants["calibration"]["camera"]["board"]["check"]
intrinsic = readdir(calibration_images, join = true)
extrinsic = intrinsic[1]
_tform, _itform, errors = CameraCalibrations.calibrationmatrices(check, extrinsic, intrinsic)

x = first.(_tform.tform)
y = last.(_tform.tform)
cols, rows = (_tform.cols, _tform.rows)
tform = Dict(pairs((; x, y, cols, rows)))
x = first.(_itform.itform)
y = last.(_itform.itform)
xs, ys = (_itform.xs, _itform.ys)
itform = Dict(pairs((; x, y, xs, ys)))

calibrationfolder = joinpath(mount_point, "home/yakir/", constants["calibration"]["camera"]["datafolder"])
isdir(calibrationfolder) || mkdir(calibrationfolder)
file = joinpath(calibrationfolder, "calibration_matrices.jld2")
@save file tform itform

run(`fusermount -u $mount_point`)

run(`ssh skyroom 'julia --project=skyroom/Project.toml -e "using SkyRoom; assemble_camera_calibration()"'`)
