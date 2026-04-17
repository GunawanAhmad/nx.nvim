package workspace

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Target struct {
	Executor string `json:"executor"`
	Command  string `json:"command"`
}

type Project struct {
	Name    string            `json:"name"`
	Root    string            `json:"root"`
	Targets map[string]Target `json:"targets"`
}

type projectJSON struct {
	Name    string            `json:"name"`
	Targets map[string]Target `json:"targets"`
}

// FindRoot walks up from dir until it finds nx.json.
func FindRoot(dir string) (string, bool) {
	path := dir
	for {
		if _, err := os.Stat(filepath.Join(path, "nx.json")); err == nil {
			return path, true
		}
		parent := filepath.Dir(path)
		if parent == path {
			return "", false
		}
		path = parent
	}
}

// DetectPackageManager returns the package manager prefix for nx (e.g. "pnpm nx").
func DetectPackageManager(root string) string {
	switch {
	case fileExists(root, "pnpm-lock.yaml"):
		return "pnpm nx"
	case fileExists(root, "yarn.lock"):
		return "yarn nx"
	case fileExists(root, "bun.lockb"), fileExists(root, "bun.lock"):
		return "bunx nx"
	case fileExists(root, "package-lock.json"):
		return "npx nx"
	default:
		return "nx"
	}
}

func fileExists(root, name string) bool {
	_, err := os.Stat(filepath.Join(root, name))
	return err == nil
}

// ListProjects scans the workspace for project.json files and returns all projects.
func ListProjects(root string) ([]Project, error) {
	var projects []Project

	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			name := d.Name()
			// skip heavy dirs
			if name == "node_modules" || name == ".git" || name == "dist" || name == ".nx" {
				return filepath.SkipDir
			}
			return nil
		}
		if d.Name() != "project.json" {
			return nil
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}

		var pj projectJSON
		if err := json.Unmarshal(data, &pj); err != nil {
			return nil
		}
		if pj.Name == "" {
			return nil
		}

		rel, _ := filepath.Rel(root, filepath.Dir(path))
		projects = append(projects, Project{
			Name:    pj.Name,
			Root:    rel,
			Targets: pj.Targets,
		})
		return nil
	})

	sort.Slice(projects, func(i, j int) bool {
		return projects[i].Name < projects[j].Name
	})

	return projects, err
}

// TargetNames returns sorted target names for a project.
func TargetNames(p Project) []string {
	names := make([]string, 0, len(p.Targets))
	for k := range p.Targets {
		names = append(names, k)
	}
	sort.Strings(names)
	return names
}

// ProjectNames returns just the names.
func ProjectNames(projects []Project) []string {
	names := make([]string, len(projects))
	for i, p := range projects {
		names[i] = p.Name
	}
	return names
}

// FindProject finds a project by name.
func FindProject(projects []Project, name string) (Project, bool) {
	for _, p := range projects {
		if p.Name == name {
			return p, true
		}
	}
	return Project{}, false
}

// FilterProjects returns projects whose name contains the query (case-insensitive).
func FilterProjects(projects []Project, query string) []Project {
	if query == "" {
		return projects
	}
	q := strings.ToLower(query)
	var out []Project
	for _, p := range projects {
		if strings.Contains(strings.ToLower(p.Name), q) {
			out = append(out, p)
		}
	}
	return out
}
