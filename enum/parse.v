import os

fn main() {
	lines := os.read_file_into_lines('kek')
	println(lines.len)
	words := []string
	for line in lines {
		if !line.contains('"') {
			continue
		}
		s := line.find_between('"', '"')
		words << s
	}
	words.sort()
	println(words.join('\n'))
}

