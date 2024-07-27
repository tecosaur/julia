function findframe(frames::StackTrace;
                    func::Union{Function, Symbol, Nothing} = nothing,
                    file::Union{Function, String, Nothing} = nothing)
    frames = collect(enumerate(frames))
    if func isa Symbol
        frames = filter(f -> last(f).func === func, frames)
    elseif func isa Function
        frames = filter(func ∘ last, frames)
    end
    if file isa String
        frames = filter(f -> String(last(f).file) == file, frames)
    elseif file isa Function
        frames = filter(f -> file(String(last(f).file)), frames)
    end
    if !isempty(frames)
        first(first(frames))
    end
end

function filterframes(frames::StackTrace;
                      func::Union{Function, Symbol, Nothing} = nothing,
                      file::Union{Function, String, Nothing} = nothing)
    if func isa Symbol
        frames = filter(f -> f.func === func, frames)
    elseif func isa Function
        frames = filter(func, frames)
    end
    if file isa String
        frames = filter(f -> String(f.file) == file, frames)
    elseif file isa Function
        frames = filter(f -> file(String(f.file)), frames)
    end
    frames
end

# FIXME: Implement
isstdlibfile(path::String) =
    startswith(abspath(path),
               normpath())

isbasefile(path::String) =
    startswith(abspath(path),
               normpath(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "base")))

"""
    getline(file::String, line::Int) -> Union{String, Nothing}

Read a single `line` from `file` and return it. In addition to
being a file on disk, `file` can also refer to this session's REPL history.

If not possible, for whatever reason, `nothing` is returned instead.
"""
function getline(file::String, line::Int)
    if isfile(file)
        for (linenum, content) in enumerate(eachline(file))
            linenum == line && return content
        end
    elseif startswith(file, "REPL[") && endswith(file, ']')
        histindex = tryparse(Int, view(file, 1+ncodeunits("REPL["):prevind(file, ncodeunits(file))))
        isnothing(histindex) && return
        get_repl_line(histindex, line)
    end
end

"""
    getline(frame::StackFrame)

Call `getline` on the line referred to by `frame`.
"""
function getline(frame::StackFrame)
    file = String(frame.file)
    file = something(Base.find_source_file(file), file)
    getline(file, frame.line)
end

"""
    get_repl_line(histindex::Int, line::Int) -> Union{String, Nothing}

Retrieve `line` from the REPL history, specifically the `histindex` entry this
session. If this cannot be done for any reason, `nothing` is returned.
"""
function get_repl_line(histindex::Int, line::Int)
    isdefined(Base, :active_repl) || return
    !isempty(Base.active_repl.interface.modes) || return
    hp = Base.active_repl.interface.modes[1].hist
    idx = hp.start_idx + histindex
    idx in eachindex(hp.history) || return
    lines = split(hp.history[idx], '\n')
    line in eachindex(lines) || return
    lines[line]
end

"""
    pprintline(io::IO, file::String, line::Int, content::AbstractString)

Print `content` to `io`, with decorations indicating that it is `line` of `file`.
"""
function pprintline(io::IO, file::String, line::Int, content::AbstractString)
    npad = max(0, 3 - ndigits(line))
    file = Base.fixup_stdlib_path(file)
    sourcedir = normpath(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "base"))
    if startswith(file, sourcedir)
        file = relpath(file, sourcedir)
    end
    if Base.stacktrace_contract_userdir()
        file = contractuser(file)
    end
    print(io, styled" $(' '^npad){shadow:$(line)╻} ", highlight(content), '\n',
          styled" $(' '^(npad+ndigits(line))){shadow:╰──╴{italic:$file}}")
end

"""
    pprintline(io::IO, file::Union{String, Symbol}, line::Int;
               deindent::Bool=false, highlighter::Function=highlight)

Print `line` of `file`, optionally `deindent`ed and highlighted with
`highlighter` to `io`.
"""
function pprintline(io::IO, file::Union{String, Symbol}, line::Int;
                    deindent::Bool=false, highlighter::Function=highlight)
    content = getline(file, line)
    isnothing(content) && return
    if deindent
        content = lstrip(content)
    end
    content = AnnotatedString(highlighter(content))
    pprintline(io, file, line, content)
end

"""
    pprintline(io::IO, frame::StackFrame; kwargs...)

Print the line referred to by `frame`, passing any keywords onto
the `pprintline(io, file, line)` method.
"""
function pprintline(io::IO, frame::StackFrame; kwargs...)
    file = String(frame.file)
    file = something(Base.find_source_file(file), file)
    pprintline(io, file, frame.line; kwargs...)
end

"""
    suspectframes(ex::Exception, trace::StackTrace) -> Union{Int, Nothing}

Examine `trace` in the context of a particular exception (`ex`),
and identify the most suspicious stackframe of `trace` by index.

When no suspicious frame can be identified, return `nothing`.
"""
function suspectframes(::Exception, ::StackTrace)
    nothing
end

suspectframes(ex::LoadError, st::StackTrace) = suspectframes(ex.error, st)

function printframes(io::IO, ex::Exception, bt::StackTrace)
    frame = suspectframes(ex, bt)
    if frame isa Int
        frame = if frame in eachindex(bt) bt[frame] end
    end
    isnothing(frame) && return
    isnothing(getline(frame)) && return
    println(io, '\n')
    pprintline(io, frame, deindent=true)
end
