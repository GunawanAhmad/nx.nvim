package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"

	"github.com/guns/nx-runner/internal/workspace"
)

func die(msg string) {
	fmt.Fprintln(os.Stderr, "nx-runner: "+msg)
	os.Exit(1)
}

func findRoot() (string, []workspace.Project) {
	cwd, _ := os.Getwd()
	root, ok := workspace.FindRoot(cwd)
	if !ok {
		die("nx.json not found in any parent directory")
	}
	projects, err := workspace.ListProjects(root)
	if err != nil {
		die("failed to list projects: " + err.Error())
	}
	return root, projects
}

func main() {
	args := os.Args[1:]
	if len(args) == 0 {
		printUsage()
		os.Exit(1)
	}

	switch args[0] {
	case "projects":
		_, projects := findRoot()
		out := workspace.ProjectNames(projects)
		if isJSON(args) {
			enc, _ := json.Marshal(out)
			fmt.Println(string(enc))
		} else {
			for _, n := range out {
				fmt.Println(n)
			}
		}

	case "targets":
		if len(args) < 2 {
			die("usage: nx-runner targets <project>")
		}
		_, projects := findRoot()
		proj, ok := workspace.FindProject(projects, args[1])
		if !ok {
			die("project not found: " + args[1])
		}
		names := workspace.TargetNames(proj)
		if isJSON(args) {
			enc, _ := json.Marshal(names)
			fmt.Println(string(enc))
		} else {
			for _, t := range names {
				fmt.Println(t)
			}
		}

	case "run":
		if len(args) < 3 {
			die("usage: nx-runner run <project> <target> [args...]")
		}
		root, _ := findRoot()
		pkgMgr := workspace.DetectPackageManager(root)
		target := args[1] + ":" + args[2]
		cmdArgs := append([]string{"run", target}, args[3:]...)
		parts := strings.Fields(pkgMgr)
		parts = append(parts, cmdArgs...)
		cmd := exec.Command(parts[0], parts[1:]...)
		cmd.Dir = root
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			os.Exit(1)
		}

	case "help", "--help", "-h":
		printUsage()

	default:
		fmt.Fprintln(os.Stderr, "unknown command: "+args[0])
		printUsage()
		os.Exit(1)
	}
}

func isJSON(args []string) bool {
	return slices.Contains(args, "--json")
}

func printUsage() {
	fmt.Print(`nx-runner — fast NX project/target runner

COMMANDS
  projects [--json]              list all projects
  targets <project> [--json]     list targets for a project
  run <project> <target> [args...]  run a target

`)
}
