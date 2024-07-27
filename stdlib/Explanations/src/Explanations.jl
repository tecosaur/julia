module Explanations

using Base.StackTraces
using Base: AnnotatedString, AnnotatedIOBuffer, annotations

using StyledStrings: StyledStrings, Face, addface!, @styled_str, styled
using JuliaSyntaxHighlighting: highlight, highlight!
using Markdown

export errinfo
public suggestfix

include("types.jl")
include("utils.jl")
include("stackframing.jl")
include("lookups.jl")
include("hints.jl")
include("builtin_errors.jl")

const ERROR_FACES = [
    :julia_error_aspect => Face(foreground = :green, inherit=:markdown_inlinecode),
    :julia_error_position => Face(foreground = :yellow, inherit=:markdown_inlinecode),
    :julia_error_value => Face(foreground = :blue, inherit=:markdown_inlinecode),
]

__init__() = foreach(addface!, ERROR_FACES)

"""
    BUILTIN_EXPLANATIONS_MODULES::Tuple{Vararg{Module}}

Modules that have been blessed, and do not need to qualify their error codes.
"""
const BUILTIN_EXPLANATIONS_MODULES = (Core, Base, Explanations)

"""
    BUILTIN_EXPLANATIONS_DIR::String

Path to the explanations folder used for explanations for on of the
`BUILTIN_EXPLANATIONS_MODULES`.
"""
const BUILTIN_EXPLANATIONS_DIR = joinpath(@__DIR__, "explanations")

"""
    BUILTIN_EXPLANATION_BASE_URL::String

Built-in explanations are expected to be published as part of the Julia manual,
and can be expected at `\$BUILTIN_EXPLANATION_BASE_URL/<code>.html`.
"""
const BUILTIN_EXPLANATION_BASE_URL =
    "https://docs.julialang.org/en/v$(VERSION.major).$(VERSION.minor)/manual/explanation_codes/"

"""
    EXPLANATION_ROOTS::Dict{Module, String}

A mapping from modules with explanations, to the directory in which their
explanation files may be found.

Without an explicit entry here, explanations will be looked for under
`src/explanations` in the `pkgdir` of the module (if possible).
"""
const EXPLANATION_ROOTS = Dict{Module, String}(
    Core => BUILTIN_EXPLANATIONS_DIR,
    Base => BUILTIN_EXPLANATIONS_DIR,
    Explanations => BUILTIN_EXPLANATIONS_DIR,
)

"""
    MAX_CODE_DIGITS::Int

The maximum number of digits of an error file code. This is used
to limit the number of 0-prefix digits checked for.
"""
const MAX_CODE_DIGITS = 4

"""
    EXPLANATION_FILE_SUFFIX::String

The expected suffix of explanation files. Only files that end with
this suffix can be automatically found.
"""
const EXPLANATION_FILE_SUFFIX = ".md"

# REVIEW: Method of hooking into `Base`. This particular approach
# has been chosen just so I can actually try developing this feature,
# but I really need to chat with people about what would be best
# once we want to make this mergeable.
function Base.show_error_explanation(io::IO, ex::Exception, st::StackTrace)
    printframes(io, ex, st::StackTrace)
    hints = errorhints(ex, st::StackTrace)
    if hints isa Hint
        hints = [hints]
    end
    if !isnothing(hints)
        println(io)
        for hint in hints
            println(io)
            printhint(io, hint)
        end
    end
    code = explanation_code(ex, st::StackTrace)
    !isnothing(code) && printcode(io, code)
end

Base.show_error_explanation(io::IO, ex::Exception, bt::Vector{Union{Ptr{Nothing}, Base.InterpreterIP}}) =
    Base.show_error_explanation(io, ex, stacktrace(bt))

"""
    HAVE_MENTIONED_ERRINFO_ERR

Signals whether or not the message
```
…  (or errinfo(err), while this is the most recent error)
```
has been printed, mentioning that `errinfo(err)` can be used.

We only want to print this once, so we can be more succinct from then on.
"""
const HAVE_MENTIONED_ERRINFO_ERR = Ref(false)

function printcode(io::IO, code::ExplanationCode)
    codestr = if code.parent in BUILTIN_EXPLANATIONS_MODULES
        string(something(code.category, ""), code.code)
    else
        string(String(nameof(code.parent)), ':',
               something(code.category, ""), code.code)
    end
    codeface = if code.category === :E
        :error
    elseif code.category === :W
        :warning
    else
        :emphasis
    end
    codehref = if code.parent in BUILTIN_EXPLANATIONS_MODULES
        BUILTIN_EXPLANATION_BASE_URL * codestr
    end
    if isnothing(codehref)
        print(io, styled"\n\n {bold,$codeface:$codestr:}")
    else
        print(io, styled"\n\n {bold,$codeface:{link=$codehref,(underline=shadow):$codestr}:}")
    end
    if isinteractive()
        lwidth = printwrapped(
            io, " For more information about this class of errors, run ",
            if code.parent in BUILTIN_EXPLANATIONS_MODULES
                highlight("errinfo(\"$codestr\")")
            else
                highlight("errinfo($(nameof(code.parent)), \"$(last(split(codestr, ':')))\")")
            end, offset = 4 + textwidth(codestr), getwidth = true)
        if !HAVE_MENTIONED_ERRINFO_ERR[]
            printwrapped(io, " (or ", highlight("errinfo(err)"), ", while this is the most recent error)";
                         offset = lwidth)
            HAVE_MENTIONED_ERRINFO_ERR[] = true
        end
    else
        jlopts = Base.JLOptions()
        optstr = if code.parent in BUILTIN_EXPLANATIONS_MODULES
            ""
        elseif jlopts.project != C_NULL
            " --project=\$($(unsafe_string(jlopts.project)))"
        else "" end
        print(io, " For more information about this error, run ",
              styled"{code:julia$optstr --explain $codestr}")
        if !isnothing(codehref)
            print(io, " or see ", codehref)
        end
    end
end

if Base.generating_output()
    include("precompile.jl")
end

end
