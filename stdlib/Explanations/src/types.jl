struct ExplanationCode
    parent::Module
    category::Union{Symbol, Nothing}
    code::UInt
end

# Errors

struct ExplanationNotFound <: Exception
    parent::Union{Module, Nothing}
    root::Union{String, Nothing}
    category::Union{Symbol, Nothing}
    code::UInt
end

function Base.showerror(io::IO, err::ExplanationNotFound)
    print(io, "ExplanationNotFound: ")
    if isnothing(err.parent)
        print(io, "Global")
    else
        print(io, styled"{emphasis:$(err.parent)}")
    end
    if isnothing(err.root)
        print(io, " has no registered explanation folder")
    else
        eid = string(something(err.category, ""), err.code)
        print(io, " explanation identifier ",
              styled"{emphasis:$eid} not found within\n {underline:$(err.root)}")
    end
end

struct ExplanationUnknown <: Exception
    ex::Exception
    trace::Union{StackTrace, Nothing}
end

#  Hints

struct Hint{M}
    kind::Symbol
    msg::M
end

# Suggestions

struct Edit
    line::Int
    content::String
    insertion::Bool
end

struct EditHunk
    edits::Vector{Edit}
end

struct Diff
    file::String
    hunks::Vector{EditHunk}
end

abstract type SuggestionApplicability end

struct MachineApplicable <: SuggestionApplicability end
struct HasPlaceholders <: SuggestionApplicability end
struct NeedsReview <: SuggestionApplicability end
struct UnknownApplicability <: SuggestionApplicability end

const Applicability =
    (Machine = MachineApplicable(),
     Placeholders = HasPlaceholders(),
     Review = NeedsReview(),
     Unspecified = UnknownApplicability())

struct Suggestion
    applicability::SuggestionApplicability
    diff::Diff
end
