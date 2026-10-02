#include <iostream>
#include <string>
#include <vector>

int main() {
    const std::vector<std::string> words{"Hello", "Sailfish", "C++"};
    for (const auto& word : words) std::cout << word << ' ';
    std::cout << '\n';
}
