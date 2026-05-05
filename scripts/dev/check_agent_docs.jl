module AgentDocsCheck

export check_agent_docs

const DEFAULT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const REQUIRED_ROOT_FILES = [
    "AGENTS.md",
    "agent-docs/README.md",
    "agent-docs/current-agent-context/INDEX.md",
    "docs/README.md",
    "llms.txt",
]

function _rel(root::AbstractString, path::AbstractString)
    return replace(relpath(path, root), '\\' => '/')
end

function _read(root::AbstractString, relpath::AbstractString)
    return read(joinpath(root, relpath), String)
end

function _md_files(root::AbstractString, relroot::AbstractString)
    base = joinpath(root, relroot)
    isdir(base) || return String[]
    files = String[]
    for (dir, _, names) in walkdir(base)
        for name in names
            if endswith(name, ".md") || name == "llms.txt" || name == "AGENTS.md"
                push!(files, _rel(root, joinpath(dir, name)))
            end
        end
    end
    return sort(files)
end

function _is_external_link(target::AbstractString)
    lower = lowercase(target)
    return startswith(lower, "http://") ||
           startswith(lower, "https://") ||
           startswith(lower, "mailto:") ||
           startswith(lower, "tel:")
end

function _strip_markdown_code(text::AbstractString)
    without_fences = replace(text, r"(?s)```.*?```" => "")
    return replace(without_fences, r"`[^`\n]*`" => "")
end

function _normalize_link_target(raw::AbstractString)
    target = strip(raw)
    if startswith(target, "<") && endswith(target, ">")
        target = target[2:end-1]
    else
        target = first(split(target))
    end
    hash = findfirst(==('#'), target)
    if hash !== nothing
        target = target[begin:prevind(target, hash)]
    end
    return strip(target)
end

function _check_markdown_links!(errors::Vector{String}, root::AbstractString, relpath::AbstractString)
    text = _strip_markdown_code(_read(root, relpath))
    base = dirname(joinpath(root, relpath))
    for match in eachmatch(r"!?\[[^\]\n]*\]\(([^)\n]+)\)", text)
        target = _normalize_link_target(String(match.captures[1]))
        isempty(target) && continue
        startswith(target, "#") && continue
        _is_external_link(target) && continue

        resolved = startswith(target, "/") ?
            normpath(joinpath(root, target[2:end])) :
            normpath(joinpath(base, target))
        if !(isfile(resolved) || isdir(resolved))
            push!(errors, "$relpath links to missing target `$target`")
        end
    end
end

function _check_required_files!(errors::Vector{String}, root::AbstractString)
    for relpath in REQUIRED_ROOT_FILES
        isfile(joinpath(root, relpath)) || push!(errors, "missing required map file `$relpath`")
    end
end

function _check_short_agents!(errors::Vector{String}, root::AbstractString)
    relpath = "AGENTS.md"
    text = _read(root, relpath)
    line_count = length(split(text, '\n'))
    line_count <= 150 || push!(errors, "`AGENTS.md` is $line_count lines; keep it as a short map/contract")
    for needle in ("llms.txt", "docs/", "agent-docs/")
        occursin(needle, text) || push!(errors, "`AGENTS.md` should point to `$needle`")
    end
end

function _check_public_readme_surface!(errors::Vector{String}, root::AbstractString)
    relpath = "README.md"
    text = _read(root, relpath)
    first_screen = join(first(split(text, '\n'), min(40, length(split(text, '\n')))), "\n")
    retired_backend = "Multi" * "Mode" * "Noise"
    retired_import = "using " * retired_backend

    startswith(text, "# FiberLab") ||
        push!(errors, "`README.md` must open with the public product name `# FiberLab`")
    occursin("using FiberLab", first_screen) ||
        push!(errors, "`README.md` first screen must show the notebook-facing `using FiberLab` API")
    !occursin(retired_import, first_screen) ||
        push!(errors, "`README.md` first screen exposes the retired backend import")
    !occursin(retired_backend, first_screen) ||
        push!(errors, "`README.md` first screen should not center the inherited backend name")
end

function _check_retired_public_vocabulary!(errors::Vector{String}, root::AbstractString)
    retired_backend = "Multi" * "Mode" * "Noise"
    retired_experiment_word = "play" * "ground"
    retired_terms = [
        retired_backend,
        "using " * retired_backend,
        retired_experiment_word,
        uppercasefirst(retired_experiment_word),
        uppercase(retired_experiment_word),
    ]
    relroots = [
        "README.md",
        "AGENTS.md",
        "llms.txt",
        "docs",
        "agent-docs",
        "scripts",
        "src",
        "test",
        "Makefile",
        "fiberlab",
        "Project.toml",
        "Manifest.toml",
    ]

    files = String[]
    for relroot in relroots
        path = joinpath(root, relroot)
        if isfile(path)
            push!(files, relroot)
        elseif isdir(path)
            for (dir, _, names) in walkdir(path)
                for name in names
                    relpath = _rel(root, joinpath(dir, name))
                    if endswith(name, ".md") || endswith(name, ".jl") ||
                       endswith(name, ".toml") || endswith(name, ".txt") ||
                       name == "Makefile" || name == "fiberlab"
                        push!(files, relpath)
                    end
                end
            end
        end
    end

    for relpath in sort(unique(files))
        text = _read(root, relpath)
        for term in retired_terms
            occursin(term, text) || continue
            push!(errors, "`$relpath` contains retired public vocabulary `$term`; use FiberLab/exploration wording")
        end
    end
end

function _check_agent_doc_registry!(errors::Vector{String}, root::AbstractString)
    readme = _read(root, "agent-docs/README.md")
    agent_root = joinpath(root, "agent-docs")
    for name in sort(readdir(agent_root))
        path = joinpath(agent_root, name)
        isdir(path) || continue
        startswith(name, ".") && continue
        occursin("$name/", readme) ||
            push!(errors, "`agent-docs/README.md` does not register `agent-docs/$name/`")
    end
end

function _check_current_context_index!(errors::Vector{String}, root::AbstractString)
    index = _read(root, "agent-docs/current-agent-context/INDEX.md")
    context_root = joinpath(root, "agent-docs", "current-agent-context")
    for name in sort(readdir(context_root))
        path = joinpath(context_root, name)
        isfile(path) || continue
        name == "INDEX.md" && continue
        endswith(name, ".md") || continue
        occursin(name, index) ||
            push!(errors, "`current-agent-context/INDEX.md` does not mention `$name`")
    end
end

function _check_no_wikilinks_or_conflicts!(errors::Vector{String}, root::AbstractString)
    for relpath in vcat(["AGENTS.md", "llms.txt"], _md_files(root, "agent-docs"), _md_files(root, "docs"))
        text = _read(root, relpath)
        if occursin(r"\[\[[^\]]+\]\]", text)
            push!(errors, "$relpath contains Obsidian-style wikilinks; use Markdown links")
        end
        if occursin("sync-conflict", relpath)
            push!(errors, "Syncthing conflict file present in docs surface: `$relpath`")
        end
    end
end

function _check_links!(errors::Vector{String}, root::AbstractString)
    files = vcat(
        ["AGENTS.md", "llms.txt"],
        _md_files(root, "agent-docs"),
        _md_files(root, "docs"),
    )
    for relpath in unique(files)
        _check_markdown_links!(errors, root, relpath)
    end
end

function check_agent_docs(; root::AbstractString=DEFAULT_ROOT)
    root = normpath(root)
    errors = String[]
    _check_required_files!(errors, root)
    isempty(errors) || return errors
    _check_short_agents!(errors, root)
    _check_public_readme_surface!(errors, root)
    _check_retired_public_vocabulary!(errors, root)
    _check_agent_doc_registry!(errors, root)
    _check_current_context_index!(errors, root)
    _check_no_wikilinks_or_conflicts!(errors, root)
    _check_links!(errors, root)
    return sort(unique(errors))
end

function main()
    errors = check_agent_docs()
    if isempty(errors)
        println("agent docs check passed")
        return 0
    end

    println(stderr, "agent docs check failed:")
    for error in errors
        println(stderr, "  - ", error)
    end
    return 1
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

end
