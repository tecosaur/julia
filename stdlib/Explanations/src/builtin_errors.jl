import Base: showerror

# For development/testing only
explanation_code(::ExplanationNotFound) = ExplanationCode(Explanations, :E, 666)
explanation_code_methoderror(::typeof(+), ::Tuple{String, String}) =
    ExplanationCode(Base, :E, 12)

## Method errors

suspectframes(::MethodError, ::StackTrace) = 1

### Method errors: -isms from other languages

function methoderrorhints(::typeof(+), (a, b)::Tuple{AbstractString, AbstractString})
    dlink = docslink("manual/strings#man-concatenation", "string concatenation section of the manual")
    [suggest(styled"Use {julia_error_value:*} instead of {julia_error_value:+} for string concatenation, see the $dlink."),]
end
methoderrorhints(::typeof(+), ::Tuple{AbstractChar, AbstractChar}) =
    suggest(styled"To apply an offset to a character use an {julia_error_aspect:integer} not a {julia_error_aspect:character}")
methoderrorhints(::typeof(*), ::Tuple{Int, AbstractString}) =
    suggest(styled"To repeat a string use the {julia_error_value:^} operator not {julia_error_value:*}")
methoderrorhints(::typeof(*), ::Tuple{Int, AbstractChar}) =
    suggest(styled"To repeat a character use the {julia_error_value:^} operator not {julia_error_value:*}")
methoderrorhints(::typeof(max), ::Tuple{AbstractArray}) =
    suggest(styled"Use {julia_error_value:maximum} not {julia_error_value:max} to find the maximum value of an array.")
methoderrorhints(::typeof(min), ::Tuple{AbstractArray}) =
    suggest(styled"Use {julia_error_value:minimum} not {julia_error_value:min} to find the minimum value of an array.")

### Method errors: initialisation mistakes

methoderrorhints(::Type{Int}, (s,)::Tuple{AbstractString}) =
    suggest(styled"To parse a string to an integer, use the form " * highlight("parse(Int, $(sprint(show, s)))"))
methoderrorhints(::Type{Float64}, (s,)::Tuple{AbstractString}) =
    suggest(styled"To parse a string to an float, use the form " * highlight("parse(Float64, $(sprint(show, s)))"))
methoderrorhints(::Type{Cmd}, (s,)::Tuple{AbstractString}) =
    note(styled"A string cannot be directly cast to a {code:Cmd}, it must be explicitly split into tokens e.g. " *
         highlight("Cmd([\"date\", \"-I\"])"))

### Method errors: conversion

function methoderrorhints(::typeof(String), ::Tuple)
    @nospecialize
    suggest(styled"To create a string from another type, use the {julia_error_value:string} function instead of {julia_error_value:convert}.")
end
function methoderrorhints(::typeof(convert), ::Tuple{Type{<:Number}, AbstractString})
    @nospecialize
    suggest(styled"To convert a numeric string to a number, use the {julia_error_value:parse} instead of {julia_error_value:convert}.")
end

### Method errors: linear algebra

methoderrorhints(::typeof(adjoint), ::Tuple{Any}) =
    note(styled"The {julia_error_value:adjoint} operation is intended for linear algebra usage — for general data manipulation see {julia_error_value:permutedims}, which is non-recursive.")
methoderrorhints(::typeof(transpose), ::Tuple{Any}) =
    note(styled"The {julia_error_value:transpose} operation is intended for linear algebra usage — for general data manipulation see {julia_error_value:permutedims}, which is non-recursive.")

### Method errors: misc

function methoderrorhints(::Number, ::Tuple)
    @nospecialize
    suggest(styled"Perhaps you forgot to use an operator such as {code:*}, {code:^}, {code:%}, {code:/}, etc. ?")
end

function methoderrorhints(::typeof(setindex!), ::Tuple{Number, Vararg{Any}})
    @nospecialize
    tip(styled"If trying to index into a multi-dimensional array, separate indices with commas: use {code:a[1, 2]} rather than {code:a[1][2]} for example.")
end

function methoderrorhints(::typeof(setindex!), (T, _...)::Tuple{DataType, Vararg{Any}})
    @nospecialize
    if !isprimitivetype(T)
        tip(styled"You can't index a type directly, perhaps you meant to index an instance of the type, \
                   in which case you should ensure that you are constructing an instance of the type properly: \
                   say using $(highlight(\"x = $(nameof(T))(args...)\")) rather than $(highlight(\"x = $(nameof(T))\")).")
    end
end

## UndefVarError

function showerror(io::IO, ex::UndefVarError)
    print(io, "UndefVarError: ")
    print(io, styled"{julia_error_value:$(ex.var)} not defined")
    if isdefined(ex, :scope)
        scope = ex.scope
        if scope isa Module
            print(io, styled" in {julia_error_aspect:$scope}")
        elseif scope === :static_parameter
            print(io, styled" in static parameter matching")
        else
            print(io, styled" in {julia_error_aspect:$scope} scope")
        end
    end
end

suspectframes(::UndefVarError, ::StackTrace) = 1

function errorhints(ex::UndefVarError)
    hints = Hint[]
    var = ex.var
    if var === :or
        push!(hints, suggest(styled"Use {julia_error_value:||} for a short-circuiting boolean OR."))
    elseif var === :and
        push!(hints, suggest(styled"Use {julia_error_value:&&} for a short-circuiting boolean AND."))
    elseif var === :help && isinteractive()
        println(io)
        # Show friendly help message when user types help or help() and help is undefined
        show(io, MIME("text/plain"), Base.Docs.parsedoc(Base.Docs.keywords[:help]))
        return
    elseif var === :quit && isinteractive()
        push!(hints, suggest(styled"To exit Julia, use {julia_error_value:Ctrl-D}, or type {julia_error_value:exit()} and press enter."))
    elseif var === :quit # non-interactive
        push!(hints, suggest(styled"To exit Julia, use {julia_error_value:exit()} (optionally {julia_error_value:exit(errorcode::Int)})"))
    end
    isdefined(ex, :scope) || return hints
    scope = ex.scope
    scope === Base && return
    if scope === :static_parameter
        push!(hints, suggest(styled"Run {code:Test.detect_unbound_args} to detect method arguments that do not fully constrain a type parameter."))
    elseif scope === :local
        push!(hints, suggest(styled"Check for an assignment to a local variable that shadows a global of the same name."))
    elseif scope isa Module
        bnd = ccall(:jl_get_module_binding, Any, (Any, Any, Cint), scope, var, true)::Core.Binding
        if isdefined(bnd, :owner)
            owner = bnd.owner
            if owner === bnd
                push!(hints, suggest(styled"Add an appropriate import or assignment. This global was declared but not assigned."))
            end
        else
            owner = ccall(:jl_binding_owner, Ptr{Cvoid}, (Any, Any), scope, var)
            if C_NULL == owner
                # No global of this name exists in this module.
                # This is the common case, so do not print that information.
                # It could be the binding was exported by two modules, which we can detect
                # by the `usingfailed` flag in the binding:
                if isdefined(bnd, :flags) && Bool(bnd.flags >> 4 & 1) # magic location of the `usingfailed` flag
                    push!(hints, suggest(
                        styled"It looks like two or more modules export different \
                               bindings with this name, resulting in ambiguity. Try explicitly \
                               importing it from a particular module, or qualifying the name \
                               with the module it should come from."))
                else
                    push!(hints, suggest(styled"Check for spelling errors or missing imports."))
                end
                owner = bnd
            else
                owner = unsafe_pointer_to_objref(owner)::Core.Binding
            end
        end
        if owner !== bnd
            # this could use jl_binding_dbgmodule for the exported location in the message too
            push!(hints, suggest(styled"This global was defined as {julia_error_value:$(owner.globalref)} but not assigned a value."))
        end
    else # not a Module
        scope = undef
    end
    accesible_modules = Module[]
    scope isa Module && push!(accesible_modules, scope)
    function novelsubmodule(modul::Module, name::Symbol)
        isdefined(modul, name) || return
        val = getglobal(modul, name)
        val isa Module || return
        val in (Core, Base, Main) && return
        parentmodule(val) in (Core, Base, Main) && return
        val
    end
    for name in names(scope, imported=true, usings=true)
        val = @something novelsubmodule(scope, name) continue
        val in accesible_modules && continue
        push!(accesible_modules, val)
        # Look for up to one level of nested modules too
        for iname in names(val, imported=true, usings=true)
            ival = @something novelsubmodule(val, iname) continue
            ival in accesible_modules && continue
            push!(accesible_modules, ival)
        end
    end
    append!(accesible_modules, setdiff([Base, Core, Main], (scope,)))
    for modul in (Base, Core)
        for name in names(modul, imported=true, usings=true)
            isdefined(modul, name) || continue
            val = getglobal(modul, name)
            val isa Module || continue
            val in accesible_modules && continue
            push!(accesible_modules, val)
        end
    end
    append!(accesible_modules, setdiff(Base.loaded_modules_order, accesible_modules))
    foundelsewhere = false
    function isfrom(name::Symbol, modul::Module, othermods::Vector{Module})
        Base.isbindingresolved(modul, name) &&
            (Base.isexported(modul, name) || Base.ispublic(modul, name)) &&
            Base.isdefined(modul, name) || return false
        val = getglobal(modul, name)
        !(val isa DataType || val isa Function) ||
            parentmodule(val) == modul || parentmodule(val) ∉ othermods
    end
    valkind(::Type) = "type"
    valkind(::Function) = "function"
    valkind(::Module) = "module"
    valkind(::Any) = "variable"
    for modul in accesible_modules
        isfrom(var, modul, accesible_modules) || continue
        push!(hints, tip(styled"A public $(valkind(getglobal(modul, var))) {julia_error_value:$var} is provided by {julia_error_aspect:$modul}."))
        foundelsewhere = true
    end
    foundelsewhere && return hints
    for modul in accesible_modules
        simnames = mostsimilar(var, names(modul))
        filter!(name -> isfrom(name, modul, accesible_modules), simnames)
        if length(simnames) == 1
            push!(hints, tip(styled"A similarly named public $(valkind(getglobal(modul, first(simnames)))) \
                                    {julia_error_value:$(first(simnames))} is provided by {julia_error_aspect:$modul}."))
        elseif !isempty(simnames)
            namesfmt = join(map(n -> styled"{julia_error_value:$n}", simnames), ", ")
            push!(hints, tip(styled"Similarly named public variables $namesfmt are provided by {julia_error_aspect:$modul}."))
        end
    end
    hints
end

## FieldError

function showerror(io::IO, ex::FieldError)
    print(io, "FieldError: ")
    print(io, styled"type {julia_error_aspect:$(nameof(ex.type))} has no field {julia_error_value:$(ex.field)}")
end

suspectframes(::FieldError, st::StackTrace) =
    @something(findframe(st, func = :getproperty),
               findframe(st, func = :getfield),
               0) + 1

function errorhints(ex::FieldError)
    fieldformat(f::Symbol) = styled"{julia_error_value:$f}"
    fieldformat(fs::Vector{Symbol}) = join(map(fieldformat, fs), ", ")
    if isprimitivetype(ex.type)
        doclink = docslink("manual/types/#Primitive-Types", "primitive type")
        suggest(styled"{julia_error_aspect:$(nameof(ex.type))} is a $doclink (directly composed of raw bits), and so {italic:does not have} fields.")
    elseif ex.type isa AbstractDict{Symbol}
        suggest(styled"If you meant to access a value of the dictionary, perhaps you wanted to use \
                       indexing syntax: $(highlight(\"dict[:$(ex.field)]\"))?")
    elseif fieldcount(ex.type) == 0
        note(styled"{julia_error_aspect:$(nameof(ex.type))} instances are singletons that have no fields at all.")
    elseif fieldcount(ex.type) == 1
        suggest(styled"Perhaps you wanted to access the (sole) field {julia_error_value:$(first(fieldnames(ex.type)))}")
    elseif fieldcount(ex.type) < 12
        closematch = mostsimilar(ex.field, fieldnames(ex.type))
        if isempty(closematch)
            closematch = collect(fieldnames(ex.type))
        end
        if length(closematch) == fieldcount(ex.type)
            suggest(styled"Perhaps you wanted to access one of the fields $(fieldformat(closematch))")
        elseif length(closematch) == fieldcount(ex.type) - 1
            suggest(styled"Perhaps you wanted to access one of the fields $(fieldformat(closematch)), {julia_error_value:$(first(setdiff(collect(fieldnames(ex.type)), closematch)))}.")
        else
            otherlist = fieldformat(mostsimilar(ex.field, setdiff(collect(fieldnames(ex.type)), closematch), threshold=0.0, adaptive=false))
            suggest(styled"Perhaps you wanted to access $(pluralise(closematch, \"the field\", \"one of the fields\")) \
                           $(fieldformat(closematch)) (other fields: $otherlist).")
        end
    else # many fields
        closematch = mostsimilar(ex.field, fieldnames(ex.type), limit=12)
        if isempty(closematch)
            closematch = mostsimilar(ex.field, fieldnames(ex.type), threshold=0.1, limit=12)
        end
        suggest("Perhaps you wanted to access one of the one of the fields $(fieldformat(closematch)), \
                 {shadow:… ($(fieldcount(ex.type) - length(closematch)) others)}.")
    end
end

## ImmutableFieldError

function showerror(io::IO, ex::ImmutableFieldError)
    print(io, "ImmutableFieldError: ")
    if ismutabletype(ex.type)
        print(io, styled"while {julia_error_aspect:$(ex.type)} is mutable, its {julia_error_value:$(ex.field)} field has been declared as {code:const} and so cannot be modified.")
    else
        print(io, styled"{julia_error_aspect:$(ex.type)} is an immutable type, and so its field {julia_error_value:$(ex.field)} cannot be modified (nor any other field).")
    end
end

suspectframes(::ImmutableFieldError, ::StackTrace) = 2

explanation_code(::ImmutableFieldError) = ExplanationCode(Base, :E, 104)

## KeyError

function showerror(io::IO, ex::KeyError)
    print(io, "KeyError: ")
    print(io, styled"key {julia_error_value:$(sprint(show, ex.key))} not found")
    if !isnothing(ex.object)
        print(io, styled" in the {julia_error_aspect:$(nameof(typeof(ex.object)))}")
    end
end

suspectframes(::KeyError, st::StackTrace) =
    @something(findframe(st, func = :get),
               findframe(st, func = :getindex),
               findframe(st, func = :pop!),
               0) + 1

function errorhints(ex::KeyError)
    isnothing(ex.object) && return
    closekeys = mostsimilar(ex.key, keys(ex.object), limit=12)
    isempty(closekeys) && return
    fmtkeys = join(map(k -> styled"{julia_error_value:$(sprint(show, k))}", closekeys), ", ")
    suggest(styled"Perhaps you wanted $(pluralise(closekeys, \"the key\", \"one of the keys\")) \
                   $(fmtkeys)?")
end

## BoundsError

function showerror(io::IO, ex::BoundsError)
    print(io, "BoundsError")
    isdefined(ex, :a) || return
    print(io, ": attempt to access ")
    summary(io, ex.a)
    isdefined(ex, :i) || return
    if ex.i isa AbstractRange
        print(io, styled" over the range {julia_error_value:$(ex.i)}")
    elseif ex.i isa AbstractString
        print(io, styled" at index {julia_error_value:$(sprint(show, ex.i))}")
    elseif length(ex.i) == 1
        print(io, styled" at index {julia_error_value:$(sprint(Base.show_index, first(ex.i)))}")
    else
        print(io, " at index [")
        for (i, x) in enumerate(ex.i)
            i > 1 && print(io, ", ")
            print(io, styled"{julia_error_value:$(sprint(Base.show_index, x))}")
        end
        print(io, ']')
    end
    print(io, '.')
end

suspectframes(::BoundsError, st::StackTrace) =
    something(findframe(st, func = :getindex), 0) + 1

function errorhints(ex::BoundsError)
    isdefined(ex, :a) && isdefined(ex, :i) || return
    if ex.a isa Array && length(ex.i) ∉ (1, ndims(ex.a))
        tip(styled"When accessing a {julia_error_aspect:$(ndims(ex.a))}-dimensional array \
                   the index should be linear or of length {julia_error_aspect:$(ndims(ex.a))} (not {julia_error_aspect:$(length(ex.i))}).")
    elseif firstindex(ex.a) == 1 && length(ex.i) == 1 && first(ex.i) == 0
        tip(styled"Julia arrays conventionally use {julia_error_aspect:1}-based indexing.")
    elseif firstindex(ex.a) == 1 && length(ex.i) == 1 && first(ex.i) < 0
        tip(styled"Julia does not use negative indices to index from the end of an array, \
                   use {julia_error_value:[end$(first(ex.i))]} instead for this.")
    elseif ndims(ex.a) == 1 || length(ex.i) == 1
        suggest(styled"Valid indices of this $(nameof(typeof(ex.a))) run from {julia_error_value:$(firstindex(ex.a))} to {julia_error_value:$(lastindex(ex.a))}.")
    else
        indformat(inds) = join(map(i -> styled"{julia_error_value:$(sprint(Base.show_index, i))}", inds), ", ")
        first_ind = indformat(Tuple(first(CartesianIndices(ex.a))))
        last_ind = indformat(Tuple(last(CartesianIndices(ex.a))))
        suggest(styled"Valid indices of this $(nameof(typeof(ex.a))) run from \
                       [$first_ind] through to [$last_ind].")
    end
end

## InexactError

function showerror(io::IO, ex::InexactError)
    print(io, "InexactError: ")
    T = first(ex.args)
    valstr = if length(ex.args) == 2
        styled"{julia_error_value:\
            $(sprint(show, MIME(\"text/plain\"), ex.args[2]))}"
    else
        join([styled"{julia_error_value:\
            $(sprint(show, MIME(\"text/plain\"), a))}"
              for a in ex.args[2:end]],
             ", ")
    end
    if nameof(T) === ex.func
        print(io, styled"$valstr cannot be {italic:exactly} converted \
                         to $(indefinitearticle(nameof(T))) {julia_error_value:$(nameof(T))}")
    else
        print(io, styled"{julia_error_position:$(ex.func)} cannot {italic:exactly} convert $valstr \
                         to $(indefinitearticle(nameof(T))) {julia_error_value:$(nameof(T))}")
    end
end

suspectframes(err::InexactError, st::StackTrace) =
    something(findframe(st, func = err.func), 0) + 1

explanation_code(::InexactError) = ExplanationCode(Base, :E, 102)

function errorhints(err::InexactError)
    if first(err.args) <: Integer && err.args[2] isa AbstractFloat
        suggest(styled"Use {julia_error_aspect:round} or {julia_error_aspect:trunc} to convert floats to their nearest integer value.")
    end
end
