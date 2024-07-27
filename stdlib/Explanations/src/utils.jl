# Functions that aid the generation of informative error messages

"""
    tryfirst(itr)

Return the first element of `itr` otherwise `nothing`.
"""
tryfirst(itr) = if !isempty(itr) first(itr) end

"""
    indefinitearticle(noun) -> String

Return the appropriate indefinite article for `noun`, either `"a"` or `"an"`.
"""
function indefinitearticle(noun::String)
    if !isempty(noun) && lowercase(first(noun)) in ('a', 'e', 'i', 'o', 'u')
        "an"
    else
        "a"
    end
end
indefinitearticle(noun) = indefinitearticle(string(noun))

pluralise(count::Integer, singular, plural) = ifelse(count == 1, singular, plural)
pluralise(items::Vector, singular, plural)  = ifelse(length(items) == 1, singular, plural)
pluralise(things::Union{<:Integer, <:Vector}, singular) =
    pluralise(things, singular, singular * 's')

"""
    printwrapped(fn::Function, dest::IO; kwargs...) -> Union{Int, Nothing}
    printwrapped(dest::IO, content...; kwargs...)   -> Union{Int, Nothing}

Either print `content` to `dest`, or run a function `fn` that prints to `dest`,
but intercept the output and wrap it to a certain width, breaking on whitespace.

The keyword arguments are as follows:
- `indent::Int = 1`, the number of indenting spaces added to each line
- `rightmargin::Int = 0`, the size of the margin used on the right
- `offset::Int = 0`, the width of text already printed on the first line
- `width::Int = last(displaysize(io))`, the width of the page
- `prefix::AbstractString = ""`, a string printed before each line
- `getwidth::Bool = false`, whether the `textwidth` of the last line should be returned
"""
function printwrapped(fn::Function, dest::IO;
                      indent::Int = 1, offset::Int = 0, rightmargin::Int = 0,
                      width::Int = last(displaysize(dest)),
                      prefix::AbstractString = "", getwidth::Bool = false)
    aio = IOContext(AnnotatedIOBuffer(), dest)
    fn(aio)
    content = read(seekstart(aio.io), AnnotatedString)
    lines = Markdown.wraplines(
        content, width - indent - rightmargin - textwidth(prefix), offset)
    for line in lines
        if line == first(lines) && offset > 0
            print(dest, ' '^max(0, indent - offset), prefix, line)
        else
            print(dest, ' '^indent, prefix, line)
        end
        line === last(lines) || println(dest)
    end
    if getwidth
        if length(lines) == 1 max(indent, offset) else indent end +
            textwidth(prefix) + textwidth(last(lines))
    end
end

printwrapped(dest::IO, content...; kwargs...) =
    printwrapped(aio -> print(aio, content...), dest; kwargs...)

"""
    stringdist(a::AbstractString, b::AbstractString; halfcase::Bool=true)

Calculate the Restricted Damerau-Levenshtein distance (aka. Optimal String
Alignment) between `a` and `b`.

This is the minimum number of edits required to transform `a` to `b`, where each
edit is a *deletion*, *insertion*, *substitution*, or *transposition* of a
character, with the restriction that no substring is edited more than once.

When `halfcase` is true, substitutions that just switch the case of a character
cost half as much.

# Examples

```jldoctest; setup = :(import Explanations.stringdist)
julia> stringdist("The quick brown fox jumps over the lazy dog",
                  "The quack borwn fox leaps ovver the lzy dog")
7

julia> stringdist("typo", "tpyo")
1

julia> stringdist("frog", "cat")
4

julia> stringdist("Thing", "thing", halfcase=true)
0.5
```
"""
function stringdist(a::AbstractString, b::AbstractString; halfcase::Bool=false)
    if length(a) > length(b)
        a, b = b, a
    end
    start = 0
    for (i, j) in zip(eachindex(a), eachindex(b))
        if a[i] == b[j]
            start += 1
        else
            break
        end
    end
    start == length(a) && return length(b) - start
    v₀ = collect(2:2:2*(length(b) - start))
    v₁ = similar(v₀)
    aᵢ₋₁, bⱼ₋₁ = first(a), first(b)
    current = 0
    for (i, aᵢ) in enumerate(a)
        i > start || (aᵢ₋₁ = aᵢ; continue)
        left = 2*(i - start - 1)
        current = 2*(i - start)
        transition_next = 0
        @inbounds for (j, bⱼ) in enumerate(b)
            j > start || (bⱼ₋₁ = bⱼ; continue)
            # No need to look beyond window of lower right diagonal
            above = current
            this_transition = transition_next
            transition_next = v₁[j - start]
            v₁[j - start] = current = left
            left = v₀[j - start]
            if aᵢ != bⱼ
                # (Potentially) cheaper substitution when just
                # switching case.
                substitutecost = if halfcase
                    aᵢswitchcap = if isuppercase(aᵢ)
                        lowercase(aᵢ)
                    elseif islowercase(aᵢ)
                        uppercase(aᵢ)
                    else aᵢ end
                    ifelse(aᵢswitchcap == bⱼ, 1, 2)
                else
                    2
                end
                # Minimum between substitution, deletion and insertion
                current = min(current + substitutecost,
                              above + 2, left + 2) # deletion or insertion
                if i > start + 1 && j > start + 1 && aᵢ == bⱼ₋₁ && aᵢ₋₁ == bⱼ
                    current = min(current, (this_transition += 2))
                end
            end
            v₀[j - start] = current
            bⱼ₋₁ = bⱼ
        end
        aᵢ₋₁ = aᵢ
    end
    if halfcase current/2 else current÷2 end
end

"""
    similarity(a::AbstractString, b::AbstractString; halfcase::Bool=true)

Return the `stringdist` as a proportion of the maximum length of `a` and `b`,
take one. When `halfcase` is true, case switches cost half as much.

# Example

```jldoctest; setup = :(import Explanations.similarity)
julia> similarity("same", "same")
1.0

julia> similarity("semi", "demi")
0.75

julia> similarity("Same", "same", halfcase=true)
0.875
```
"""
similarity(a::AbstractString, b::AbstractString; halfcase::Bool=true) =
    1 - stringdist(a, b; halfcase) / max(length(a), length(b))

similarity(a::Symbol, b::Symbol) = similarity(String(a), String(b))

similarity(a::AbstractChar, b::AbstractChar) = Float64(a == b)

similarity(a::Real, b::Real) = 1 - abs((a - b) / max(a, b))

similarity(a::Integer, b::Integer) = 1 - abs((a - b) / max(a, b))

function similarity(a::Integer, b::Real)
    if a == b
        prevfloat(1.0)
    else
        similarity(Float64(a), b)
    end
end

similarity(a::Real, b::Integer) = similarity(b, a)

similarity(::Any, ::Any) = 0.0

function similarity(::Type{A}, ::Type{B}) where {A, B}
    @nospecialize
    A === B && return 1.0
    asup, bsup = Type[supertype(A)], Type[supertype(B)]
    while last(asup) != Any
        push!(asup, supertype(last(asup)))
    end
    while last(bsup) != Any
        push!(bsup, supertype(last(bsup)))
    end
    sum(ap === bp for (ap, bp) in zip(reverse(asup), reverse(bsup))) /
        (max(length(asup), length(bsup)) + 1)
end

function similarity(a::AbstractVector, b::AbstractVector;
                    nsamples::Int=min(2^max(length(a), length(b)), 1000))
    jointlen = length(eachindex(a, b))
    orderedsim = sum(similarity(a[i], b[i]) for i in eachindex(a, b)) / jointlen
    ainds, binds = eachindex(a), eachindex(b)
    a0, b0 = copy(a), copy(b)
    permsims = Float64[]
    for _ in 1:nsamples
        ai, aj = rand(ainds), rand(ainds)
        a0[ai], a0[aj] = a0[aj], a0[ai]
        bi, bj = rand(binds), rand(binds)
        b0[bi], b0[bj] = b0[bj], b0[bi]
        push!(permsims, sum(similarity(a0[i], b0[i]) for i in eachindex(a0, b0)) / (jointlen + 1))
    end
    count(<(orderedsim), permsims) / nsamples * max(orderedsim, maximum(permsims)) *
        similarity(length(a), length(b))
end

similaritythreshold(ref::String, alts::Vector) =
    1 - log1p(1 / (1 + length(ref) ÷ 3))

similaritythreshold(ref::Symbol, alts::Vector) =
    similaritythreshold(String(ref), alts)

similaritythreshold(_, alts::Vector) = 1 / (1 + length(alts))

"""
    mostsimilar(ref::T, alts::Vector{T};
                threshold::Float64 = <automagic value>,
                adaptive::Bool = true,
                atleast::Int = 0, limit::Int = length(alts))) -> Vector{T}

Filter `alts` to elements that are evaluated as being above a `threshold`
similarity to `ref` (evaluated with `similarity`), and order the most
similar element first. If `adaptive` is set, the threshold will be adjusted
adaptively to the similarity scores.

Between `atleast` and `limit` items from `alts` are returned.
"""
function mostsimilar(ref::T, alts::Vector{T};
                     threshold::Float64 = similaritythreshold(ref, alts),
                     adaptive::Bool = true,
                     atleast::Int = 0,
                     limit::Int = length(alts), kwargs...) where {T}
    threshold = clamp(threshold, 0.0, 1.0)
    similarities = [similarity(ref, a; kwargs...) for a in alts]
    if adaptive
        threshold = max(adaptivethreshold(similarities, threshold), threshold / 2)
    end
    goodenough = findall(>=(threshold), similarities)
    if length(goodenough) < atleast
        threshold = sort(similarities)[atleast]
        goodenough = findall(>=(threshold), similarities)
    end
    alts[goodenough[sortperm(similarities[goodenough], rev=true)][1:min(limit,end)]]
end

"""
    adaptivethreshold(simscores::Vector{Float64}, factor::Float64) -> Float64

Adaptively determine a sensible threshold for `simscores`.

This searches for an inflection point in the sorted scores, then backtracks
until the (fractional) ratio between adjacent scores fulfils the condition
`ratio / (1 + ratio) ≥ factor`.
"""
function adaptivethreshold(simscores::Vector{Float64}, factor::Float64)
    simsorted = sort(simscores, rev=true)
    simdrops = diff(simsorted)
    isempty(simdrops) && return factor
    simtrend = diff(simdrops)
    npre = if isempty(simtrend) 1 else last(findmax(simtrend)) end
    threshold = simsorted[npre]
    snext = simsorted[min(npre+1, lastindex(simsorted))]
    while npre > 0
        simratio = simsorted[npre] / snext
        simast = simratio / (1 + simratio)
        simast >= factor && break
        npre -= 1
        threshold = if npre > 0 simsorted[npre] else factor end
    end
    threshold
end

mostsimilar(ref::T, alts::Vector{<:T}; kwargs...) where {T} =
    mostsimilar(ref, Vector{T}(alts); kwargs...)

function mostsimilar(ref::T, itr; kwargs...) where {T}
    if Base.isiterable(typeof(itr))
        mostsimilar(ref, collect(itr); kwargs...)
    else
        Vector{T}()
    end
end

# Worst case fallback
# mostsimilar(ref::T, ::Vector; kwargs...) where {T} = Vector{T}()

"""
    longest_common_subsequence(a, b)

Find the longest common subsequence of `b` within `a`, returning the indices of
`a` that comprise the subsequence.

This function is intended for strings, but will work for any indexable objects
with `==` equality defined for their elements.

# Example

```jldoctest; setup = :(import Explanations.longest_common_subsequence)
julia> longest_common_subsequence("same", "same")
4-element Vector{Int64}:
 1
 2
 3
 4

julia> longest_common_subsequence("fooandbar", "foobar")
6-element Vector{Int64}:
 1
 2
 3
 7
 8
 9
```
"""
function longest_common_subsequence(a, b)
    lengths = zeros(Int, length(a) + 1, length(b) + 1)
    for (i, x) in enumerate(a), (j, y) in enumerate(b)
        lengths[i+1, j+1] = if x == y
            lengths[i, j] + 1
        else
            max(lengths[i+1, j], lengths[i, j+1])
        end
    end
    subsequence = Int[]
    x, y = size(lengths)
    aind, bind = eachindex(a) |> collect, eachindex(b) |> collect
    while lengths[x,y] > 0
        if a[aind[x-1]] == b[bind[y-1]]
            push!(subsequence, x-1)
            x -=1; y -= 1
        elseif lengths[x, y-1] > lengths[x-1, y]
            y -= 1
        else
            x -= 1
        end
    end
    reverse(subsequence)
end

"""
    issubseq(a, b)

Return `true` if `a` is a subsequence of `b`, `false` otherwise.

## Examples

```jldoctest; setup = :(import Explanations.issubseq)
julia> issubseq("abc", "abc")
true

julia> issubseq("adg", "abcdefg")
true

julia> issubseq("gda", "abcdefg")
false
```
"""
issubseq(a, b) = length(longest_common_subsequence(a, b)) == length(a)

"""
    highlight_lcs(io::IO, a::String, b::String;
                  before::String="\\e[1m", after::String="\\e[22m",
                  invert::Bool=false)

Print `a`, highlighting the longest common subsequence between `a` and `b` by
inserting `before` prior to each subsequence region and `after` afterwards.

If `invert` is set, the `before`/`after` behaviour is switched.
"""
function highlight_lcs(io::IO, a::String, b::String;
                       before::String="\e[1m", after::String="\e[22m",
                       invert::Bool=false)
    seq = longest_common_subsequence(collect(a), collect(b))
    seq_pos = firstindex(seq)
    in_lcs = invert
    for (i, char) in enumerate(a)
        if seq_pos < length(seq) && seq[seq_pos] < i
            seq_pos += 1
        end
        if in_lcs != (i == seq[seq_pos])
            in_lcs = !in_lcs
            get(io, :color, false) && print(io, ifelse(in_lcs ⊻ invert, before, after))
        end
        print(io, char)
    end
    get(io, :color, false) && print(io, after)
end
