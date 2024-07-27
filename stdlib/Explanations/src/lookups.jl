"""
    explanation_code(ex::Exception, st::StackTrace) -> Union{ExplanationCode, Nothing}

Lookup the `ExplanationCode` that relates to a particular exception, identfied
using the value of the exception (`ex`) and stacktrace (`st`)

When implementing explanation mappings, this function may be directly overloaded
or either of the two fallbacks:

```julia
explanation_code(ex::Exception, st::StackTrace) = explanation_code(ex)
explanation_code(ex::Exception) = explanation_code(typeof(ex))
```

When no mapping has been defined, `nothing` is returned.

See also: `explanation_code_methoderor`
"""
function explanation_code end

explanation_code(::Type{<:Exception}) = nothing
explanation_code(ex::Exception) = explanation_code(typeof(ex))
explanation_code(ex::Exception, st::StackTrace) = explanation_code(ex)

explanation_code(ex::LoadError, st::StackTrace) = explanation_code(ex.error, st)

explanation_code(ex::MethodError) = explanation_code_methoderror(ex.f, ex.args)

"""
    explanation_code_methoderror(fn::Function, args::Tuple) -> Union{ExplanationCode, Nothing}

Lookup the `ExplanationCode` that relates to a method error that arose when
trying to call `fn(args...)`.

This is the function that `explanation_code(::MethodError)` dispatches to.
"""
function explanation_code_methoderor end

explanation_code_methoderror(::Any, ::Any) = nothing

"""
    explanation_file(root::String, category::Union{Symbol, Nothing}, code::UInt) -> Union{String, Nothing}

Look for an explanation file under `root` that details `code` (optionally of a
particular `category`).

See also: `explanation_lookup`
"""
function explanation_file(root::String, category::Union{Symbol, Nothing}, code::UInt)
    for zpad in ndigits(code):MAX_CODE_DIGITS
        efile = joinpath(root, if isnothing(category)
            lpad(code, zpad, '0') * EXPLANATION_FILE_SUFFIX
        else
            String(category) * lpad(code, zpad, '0') * EXPLANATION_FILE_SUFFIX
        end)
        isfile(efile) && return efile
    end
end

"""
    explanation_lookup(root::String, category::Union{Symbol, Nothing}, code::UInt) -> Markdown.MD

Look for an explanation file under `root` that details `code` (optionally of a
particular `category`). If no explanation can be found an `ExplanationNotFound`
error is raised.

See also: `explanation_file`
"""
function explanation_lookup(root::String, category::Union{Symbol, Nothing}, code::UInt)
    efile = explanation_file(root, category, code)
    isnothing(efile) &&
        throw(ExplanationNotFound(nothing, root, category, code))
    Markdown.MD(Any[open(Markdown.parse, efile)])
end

"""
    explanation_lookup(code::ExplanationCode)

Look for an explanation for `code`, by appropriately calling
`explanation_lookup(root, category, code)`.
"""
function explanation_lookup(code::ExplanationCode)
    root = get(EXPLANATION_ROOTS, code.parent, nothing)
    if isnothing(root) && !isnothing(pkgdir(code.parent))
        root = joinpath(pkgdir(code.parent), "src", "explanations")
    end
    isnothing(root) &&
        throw(ExplanationNotFound(code.parent, root, code.category, code.code))
    explanation_lookup(root, code.category, code.code)
end

"""
    errinfo([io::IO], ex::Exception, [st::StackTrace])
    errinfo([io::IO], exs::Base.ExceptionStack)
    errinfo([io::IO], code::ExplanationCode)
    errinfo([io::IO, mod::Module], code::AbstractString)
    errinfo([io::IO, mod::Module], category::Symbol, code::Integer)

Print a detailed help message about an exception. The exception can be
identified in a number of ways:
- As an explanation `code` string, e.g. `"E123"`
- As a `category` and `code`, e.g. `:E, 123`
- As an exception `ex`, optionally with a stacktrace `st`
- As an exception stack, `exs`

Optionally, the `io` written to and the `mod`ule the code belongs to may be
provided.

When no explanation can be found, an error is raised unless an exception stack
was provided (in which case a warning is printed instead).
"""
function errinfo(io::IO, code::ExplanationCode)
    info = explanation_lookup(code)
    if io == stdout
        display(info)
    else
        show(io, MIME("text/plain"), info)
    end
end

function errinfo(io::IO, category::Union{Symbol, Nothing}, code::Integer)
    info = explanation_lookup(BUILTIN_EXPLANATIONS_DIR, category, UInt(code))
    if io == stdout
        display(info)
    else
        show(io, MIME("text/plain"), info)
    end
end

function errinfo(io::IO, mod::Module, category::Union{Symbol, Nothing}, code::Integer)
    errinfo(io, ExplanationCode(mod, category, UInt(code)))
end

function errinfo(io::IO, code::AbstractString)
    dsplit = findfirst(isdigit, code)
    category = if dsplit > 1
        Symbol(code[1:dsplit-1])
    end
    codenum = parse(UInt, @view code[dsplit:end])
    errinfo(io, category, codenum)
end

function errinfo(io::IO, mod::Module, code::AbstractString)
    dsplit = findfirst(isdigit, code)
    category = if dsplit > 1
        Symbol(code[1:dsplit-1])
    end
    codenum = parse(UInt, @view code[dsplit:end])
    errinfo(io, ExplanationCode(mod, category, codenum))
end

function errinfo(io::IO, ex::Exception)
    code = explanation_code(ex)
    isnothing(code) && throw(ExplanationUnknown(ex, nothing))
    errinfo(io, code)
end

function errinfo(io::IO, ex::Exception, st::StackTrace)
    code = explanation_code(ex, st)
    isnothing(code) && throw(ExplanationUnknown(ex, st))
    errinfo(io, code)
end

function errinfo(io::IO, exs::Base.ExceptionStack)
    for (; exception, backtrace) in exs
        try
            errinfo(io, exception, backtrace)
        catch err
            if err isa ExplanationUnknown
                @warn "No explanation associated with the $(typeof(exception))"
            else
                rethrow()
            end
        end
    end
end

errinfo(code::ExplanationCode) = errinfo(stdout, code)
errinfo(mod::Module, category::Symbol, code::Integer) = errinfo(stdout, mod, category, code)
errinfo(mod::Module, code::AbstractString) = errinfo(stdout, mod, code)
errinfo(category::Symbol, code::Integer) = errinfo(stdout, category, code)
errinfo(code::AbstractString) = errinfo(stdout, code)
errinfo(ex::Exception) = errinfo(stdout, ex)
errinfo(exs::Base.ExceptionStack) = errinfo(stdout, exs)
