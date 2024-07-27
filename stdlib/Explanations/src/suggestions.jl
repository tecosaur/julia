
"""
    suggestfix(ex::Exception, st::StackTrace) -> Union{Tuple{Diff, SuggestionApplicability}, Nothing}

If possible, identify a likely fix for `ex` which occurred with stacktrace `st`.

!!! warning "TODO"
    Identify sensible return format, we need to give something like a small diff
"""
function suggestfix(ex::Exception, st::StackTrace)
    # TODO: implement
end
