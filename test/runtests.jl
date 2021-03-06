using CUDAnative, CUDAdrv
using Base.Test

# NOTE: all kernel function definitions are prefixed with @eval to force toplevel definition,
#       avoiding boxing as seen in https://github.com/JuliaLang/julia/issues/18077#issuecomment-255215304

@test devcount() > 0

include("base.jl")

include("codegen.jl")

# NOTE: based on test/pkg.jl::grab_outputs, only grabs STDOUT without capturing exceptions
macro grab_output(ex)
    quote
        OLD_STDOUT = STDOUT

        foutname = tempname()
        fout = open(foutname, "w")

        local ret
        local caught_ex = nothing
        try
            redirect_stdout(fout)
            ret = $(esc(ex))
        catch ex
            caught_ex = nothing
        finally
            redirect_stdout(OLD_STDOUT)
            close(fout)
        end
        out = readstring(foutname)
        rm(foutname)
        if caught_ex != nothing
            throw(caught_ex)
        end

        ret, out
    end
end

# Run some code on-device, returning captured standard output
macro on_device(exprs)
    @gensym kernel_fn
    quote
        let
            @eval function $kernel_fn()
                $exprs

                return nothing
            end

            @cuda (1,1) $kernel_fn()
            synchronize()
        end
    end
end

dev = CuDevice(0)
if capability(dev) < v"2.0"
    warn("native execution not supported on SM < 2.0")
else
    ctx = CuContext(dev, CUDAdrv.SCHED_BLOCKING_SYNC)

    include("execution.jl")
    include("array.jl")
    include("intrinsics.jl")
end
