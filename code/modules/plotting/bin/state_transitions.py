import sys
from helper import *

def parse_data():
    f = open(raw_input(''),'r')
    xs = f.readlines()
    d = dict()
    tot = 0
    for row in xs:
        ys = ''.join(filter(lambda x: "[] \n\'".find(x) == -1,row)).split(',')
        ys = [] + filter(lambda x: x != '' and x != '\n',ys)
        transes = zip(ys,ys[1:])
        for trans in transes:
            if not trans in d:
                d[trans] = 1
            else:
                d[trans] = d[trans] + 1
            tot = tot + 1
    return (d,tot)


def gen_tuple(d,tot):
    xs = []
    for trans in sorted([(status_names()[i],status_names()[j]) for i in status_names() for j in status_names()]):
        if trans in d:
           xs = xs + [(d[trans]/float(tot))*100]
        else:
           xs = xs + [0]
    return tuple(xs)

def gen_tex_file():
    (d,tot) = parse_data()
    t = gen_tuple(d,tot)
    st = '''
    \\begin{table}
    \\begin{tabular}{r|ccccc}
                    & DEACTIVATED & EXPIRED & FAILED & OK & STOPPED \\\\
        \hline
        DEACTIVATED & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% \\\\
        EXPIRED     & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% \\\\
        FAILED      & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% \\\\
        OK          & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% \\\\
        STOPPED     & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% & %5.2f\\%% 
      \\end{tabular}
    \\caption{Procentage of state transitions hit}
    \\end{table} 
    ''' % t
    sys.stderr.write(st)
    print st

if __name__ == "__main__":
    gen_tex_file()   
