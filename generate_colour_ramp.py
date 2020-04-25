import sys, subprocess
cols = sys.argv[1].replace("_", " ")
steps = sys.argv[2].split(",")

assert sys.argv[3] in ('exact', 'range')
mode = sys.argv[3]

def mult(val, fraction):
    if val[-1] == '%':
        return "{}%".format(float(val[:-1])*(1-fraction))
    else:
        val = float(val)
        if val == 0:
            return str(val-fraction)
        else:
            return str(val*(1-fraction))

gradients = subprocess.check_output("pastel gradient -n {} {} | pastel format rgb | tr -dc '0-9,\n'".format(len(steps), cols), shell=True).split()

for i in range(0, len(steps)):
    if i == 0:
        print "{},{}".format(steps[i], gradients[i])
    else:
        if mode == 'exact':
            print "{},{}".format(mult(steps[i], 1e-10), gradients[i-1])
        else:
            pass
        print "{},{}".format(steps[i], gradients[i])


print "nv,80,140,215"
