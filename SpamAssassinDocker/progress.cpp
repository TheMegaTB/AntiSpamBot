#include <iostream>
#include <string>
#include <cmath>
#include <stdlib.h>

using namespace std;

int main(int argc, char** argv) {
	if (argc != 3)
		cout << "Bad Input" << endl;

	double progress = ::atof(argv[1]);
	double total = ::atof(argv[2]);

	int barWidth = 100;
	int barProgress = round(progress / total * barWidth);

	int barFill = barWidth - barProgress;

	for (int i = 0; i < barProgress; i++) cerr << "#";
	for (int i = 0; i < barFill; i++) cerr << "-";

	cerr << " " << (int) round(progress) << "/" << (int) round(total) << "\r";
}
