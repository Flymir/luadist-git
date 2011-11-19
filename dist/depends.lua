-- Utility functions for dependencies

module ("dist.depends", package.seeall)

local cfg = require "dist.config"
local mf = require "dist.manifest"
local sys = require "dist.sys"
local const = require "dist.constraints"

-- Return all packages with specified names from manifest
function find_packages(package_names, manifest)

    if type(package_names) == "string" then package_names = {package_names} end
    manifest = manifest or mf.get_manifest()

    assert(type(package_names) == "table", "depends.find_packages: Argument 'package_names' is not a table or string.")
    assert(type(manifest) == "table", "depends.find_packages: Argument 'manifest' is not a table.")

    local packages_found = {}

    -- TODO reporting when no candidate for some package is found ??

    -- find matching packages in manifest
    for _, pkg_to_find in pairs(package_names) do
        for _, repo_pkg in pairs(manifest) do
            if repo_pkg.name == pkg_to_find then
                table.insert(packages_found, repo_pkg)
            end
        end
    end

    return packages_found
end

-- Return manifest consisting of packages installed in specified deploy_dir directory
function get_installed(deploy_dir)

    deploy_dir = deploy_dir or cfg.root_dir

    assert(type(deploy_dir) == "string", "depends.get_installed: Argument 'deploy_dir' is not a string.")

    local distinfos_path = deploy_dir .. "/" .. cfg.distinfos_dir
    local manifest = {}

    -- from all directories of packages installed in deploy_dir
    for dir in sys.get_directory(distinfos_path) do
        if sys.is_dir(distinfos_path .. "/" .. dir) then
            -- load the dist.info file
            for file in sys.get_directory(distinfos_path .. "/" .. dir) do
                if sys.is_file(distinfos_path .. "/" .. dir .. "/" .. file) then
                    table.insert(manifest, mf.load_distinfo(distinfos_path .. "/" .. dir .. "/" .. file))
                end
            end

        end
    end

    return manifest
end


-- Resolve dependencies and return all packages needed in order to install 'packages' into 'deploy_dir'
function get_dependencies(packages, deploy_dir)
    if not packages then return {} end

    deploy_dir = deploy_dir or cfg.root_dir
    if type(packages) == "string" then packages = {packages} end

    assert(type(packages) == "table", "depends.get_dependencies: Argument 'packages' is not a table or string.")
    assert(type(deploy_dir) == "string", "depends.get_dependencies: Argument 'deploy_dir' is not a string.")

    -- get manifest
    local manifest = mf.get_manifest()

    -- find matching packages
    -- TODO add ability to specify verion constraints?
    local want_to_install = find_packages(packages, manifest)

    -- find installed packages
    local installed = get_installed(deploy_dir)

    -- table of packages needed to install (will be returned)
    local to_install = {}

    -- for all packages wanted to install
    for k, pkg in pairs(want_to_install) do
        want_to_install[k] = nil

        -- whether pkg is already in installed table
        local pkg_is_installed = false

        -- for all packages in table 'installed'
        for _, installed_pkg in pairs(installed) do

            -- TODO add 'provides' check & version checks

            -- check if pkg is in installed
            if pkg.name == installed_pkg.name then
                pkg_is_installed = true
                break
            end

            -- check for conflicts of package to install
            if pkg.conflicts then
                for _, conflict in pairs (pkg.conflicts) do
                    if conflict == installed_pkg.name then
                        return nil, "Package '" .. pkg.name .. "' conflicts with '" .. installed_pkg.name .. "'."
                    end
                end
            end

            -- check for conflicts of installed package
            if installed_pkg.conflicts then
                for _, conflict in pairs (installed_pkg.conflicts) do
                    if conflict == pkg.name then
                        return nil, "Installed package '" .. installed_pkg.name .. "' conflicts with '" .. pkg.name .. "'."
                    end
                end
            end
        end


        -- if pkg's not in installed and passed all of the above tests
        if not pkg_is_installed then

            -- whether pkg has any dependencies
            local pkg_has_depends = false

            -- dependencies of pkg
            local depends_to_install = {}

            -- check if pkg's dependencies are satisfied
            if pkg.depends then
                pkg_has_depends = true

                -- for all dependencies of pkg
                for _, depend in pairs(pkg.depends) do
                    local dep_name, dep_constraint = split_name_constraint(depend)

                    -- find candidates to pkg's dependencies
                    local depend_candidates = find_packages(dep_name, manifest)

                    -- filter candidates according to the constraint
                    depend_candidates = filter_packages(depend_candidates, dep_constraint)

                    -- collect suitable candidates for this pkg's dependency
                    if depend_candidates and #depend_candidates > 0 then
                        for _, depend_candidate in pairs(depend_candidates) do
                            table.insert(depends_to_install, depend_candidate)
                        end
                    else
                        return nil, "No suitable candidate for dependency '" .. dep_name .. "' of package '" .. pkg.name .."' found."
                    end
                end
            end

            -- add all pkg's dependencies to table of packages wanted to install
            if pkg_has_depends then
                for _, depend in pairs(depends_to_install) do
                    table.insert(want_to_install, depend)
                end
            end

            -- add pkg to the fake table of installed packages
            table.insert(installed, pkg)

            -- add pkg to the table of packages to install
            table.insert(to_install, pkg)
        end
    end

    return to_install
end

-- Return package name and version constraint from full package version constraint specification
-- E. g.:
--          for 'luaexpat-1.2.3'  return:  'luaexpat' , '1.2.3'
--          for 'luajit >= 1.2'   return:  'luajit'   , '>=1.2'
function split_name_constraint(version_constraint)
    assert(type(version_constraint) == "string", "depends.split_name_constraint: Argument 'version_constraint' is not a string.")

    local split = version_constraint:find("[%s=~<>-]+%d") or version_constraint:find("[%s=~<>-]+scm")

    if split then
        return version_constraint:sub(1, split - 1), version_constraint:sub(split):gsub("[%s-]", "")
    else
        return version_constraint, nil
    end
end

-- Return only packages that satisfy specified constraint
function filter_packages(packages, constraint)

    if type(packages) == "string" then packages = {packages} end

    assert(type(packages) == "table", "depends.filter_packages: Argument 'packages' is not a string or table.")
    assert(type(constraint) == "string", "depends.filter_packages: Argument 'constraint' is not a string.")

    local passed_pkgs = {}

    for _, pkg in pairs(packages) do
        if satisfies_constraint(pkg.version, constraint) then
            table.insert(passed_pkgs, pkg)
        end
    end

    return passed_pkgs
end

-- Return if version satisfies the specified constraint
function satisfies_constraint(version, constraint)

    assert(type(version) == "string", "depends.satisfies_constraint: Argument 'version' is not a string.")
    assert(type(constraint) == "string", "depends.satisfies_constraint: Argument 'constraint' is not a string.")

    return const.constraint_satisfied(version, constraint)
end