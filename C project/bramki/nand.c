#include "nand.h"
#include <stdlib.h>
#include <errno.h>
#include <stdio.h>

typedef struct nand_ind nand_ind;
struct nand_ind {
    nand_t* gate;
    int ind; // indeks potrzebny do odlaczania bramek od siebie
};

typedef struct pair pair;
struct pair {
    int path;
    bool sig;
};

struct nand{
    nand_ind *inputs;  //bramki podpiete do wejsc tej bramki
    nand_ind *pinned_to; //bramki odbierajace sygnal tej bramki
    unsigned n; //ilosc wejsc
    bool visited;// do odpetlania nand_evaluate
    bool calculated; // bramka policzona juz w pojedynczym wywolaniu nand_evaluate
    pair parameters; // parametry bramki do nand_evaluate
    bool if_sig; // czy to sygnal boolowski (sztuczna bramka)
    const bool *val; // wartosc sygnalu boolowskiego
    int r; // rozmiar tablicy z bramkami odbierajacych sygnal tej bramki
    int c; //indeks ostatniej bramki podpietej do wyjscia 
    int nu; // liczba NULLI w tablicy w powstalych w wyniku odpinania
};

unsigned max(unsigned a, unsigned b) {
    if (a > b) return a;
    return b;
}

nand_t* nand_new(unsigned n) {
    nand_t* new_gate = (nand_t*)malloc(sizeof(nand_t));
    if (!new_gate) {
        errno = ENOMEM;
        return NULL;
    }

    new_gate->n = n;
    if (n) {
        new_gate->inputs = (nand_ind*)malloc(n * sizeof(nand_ind));
        if (!new_gate->inputs) {
            errno = ENOMEM;
            free(new_gate);
            new_gate = NULL;
            return NULL;
        }

        for (unsigned i = 0; i < n; i++) new_gate->inputs[i].gate = NULL;
    }
    else {
        new_gate->inputs = NULL;
    }

    new_gate->pinned_to = (nand_ind*)malloc(sizeof(nand_ind));
    if (new_gate->pinned_to == NULL) {
        errno = ENOMEM;
        free(new_gate->inputs);
        new_gate->inputs = NULL;
        free(new_gate);
        new_gate = NULL;
        return NULL;
    }

    new_gate->pinned_to[0].gate = NULL;
    new_gate->pinned_to[0].ind = -1;
    new_gate->c = -1;
    new_gate->nu = 0;
    new_gate->r = 1;
    new_gate->visited = false;
    new_gate->if_sig = false;
    new_gate->val = NULL;
    new_gate->calculated = false;
    return new_gate;
}

//usuniecie atrapy bramki (sygnalu boolowskiego)
void delete_signal(nand_t *g) {
    free(g->pinned_to);
    g->pinned_to = NULL;
    g->val = NULL;
    free(g);
    g = NULL;
}

void nand_delete(nand_t *g) {
    if (!g) return;
    else if (g->inputs) {
        for (unsigned i = 0; i < g->n; i++) {
            if (g->inputs[i].gate != NULL && g->inputs[i].gate->if_sig == true) { 
                delete_signal(g->inputs[i].gate);
            }
            else if (g->inputs[i].gate) {
                // jesli jakas bramka na ta wskazuje to ustawiamy wskaznik na NULL,
                // w tablicy wejsc pojawia sie dziura
                g->inputs[i].gate->pinned_to[g->inputs[i].ind].gate = NULL;
                g->inputs[i].gate->nu += 1;
                g->inputs[i].gate = NULL;
            }
        }
    }
    free(g->inputs);
    g->inputs = NULL;

    // jesli jakas bramka na ta wskazuje ustawiamy wskaznik na NULL,
    for(int i = 0; i < g->r; ++i) 
        if(g->pinned_to[i].gate) 
            g->pinned_to[i].gate->inputs[g->pinned_to[i].ind].gate = NULL;
    
    free(g->pinned_to);
    g->pinned_to = NULL;

    free(g);
    g = NULL;
    return;
}

int nand_connect_nand(nand_t *g_out, nand_t *g_in, unsigned k) {
    if (!g_out || !g_in || k >= g_in->n) {
        errno = EINVAL;
        return -1;
    }

    //jezeli bramka byla wczesniej podpieta do sygnalu boolowskiego, usuwamy jej atrape
    // (kazda bramka do ktorej podpinamy sygnal ma swoja wlasna oddzielna atrape sygnalu)
    if (g_in->inputs[k].gate && g_in->inputs[k].gate->if_sig) {
        delete_signal(g_in->inputs[k].gate);
    }
    else if (g_in->inputs[k].gate) {
        // jesli jakas bramka byla podpieta do wejscia, to odpinamy
        g_in->inputs[k].gate->pinned_to[g_in->inputs[k].ind].gate = NULL;
        g_in->inputs[k].gate->nu += 1;
    }
    // dla bramki g_out nie musimy nic opinac poniewaz dla kazdej kolejnej bramki
    // do ktorej g_out podepniemy posiada nowe miejsce w tablicy pinned_to, bo zwiekszamy c o 1
    g_in->inputs[k].gate = g_out;
    g_out->c += 1;


    //skonczyl sie rozmiar tablicy? to powiekszamy.
    if (g_out->c + 1 >= g_out->r) {
        nand_ind* temp = g_out->pinned_to;
        g_out->r *= 2;
        g_out->pinned_to = (nand_ind*)realloc(g_out->pinned_to, sizeof(nand_ind) * (g_out->r));
        if (!g_out->pinned_to) {
            errno = ENOMEM;
            g_out->pinned_to = temp;
            return -1;
        }
        for (int i = g_out->r/2; i < g_out->r; ++i) g_out->pinned_to[i].gate = NULL;
    }

    g_out->pinned_to[g_out->c].gate = g_in;
    g_out->pinned_to[g_out->c].ind = k;
    g_in->inputs[k].ind = g_out->c;
    return 0;
} 

int nand_connect_signal(bool const *s, nand_t *g, unsigned k) {
    if (!s || !g || k >= g->n) {
        errno = EINVAL;
        return -1;
    }

    nand_t* new_signal = nand_new(0);

    if (!new_signal) return -1;
    
    new_signal->val = s;
    new_signal->if_sig = true;
    
    //usuwamy atrape bramki sygnalu ktorego miejsce zostanie zajete
    if (g->inputs[k].gate && g->inputs[k].gate->if_sig) {
        delete_signal(g->inputs[k].gate);
    }
    else if (g->inputs[k].gate) {
        // odpinamy bramke zajmujaca miejsce przeznaczone dla sygnalu
        g->inputs[k].gate->pinned_to[g->inputs[k].ind].gate = NULL;
        g->inputs[k].gate->nu += 1;
    }

    g->inputs[k].gate = new_signal;
    return 0;
}


//najpierw funckja evaluate zaglebia sie w wejscia oznaczajac je jako odwiedzone
//nastepnie sie wynurza ustalajac wynik i odznaczajac bramki
pair evaluate(nand_t *g) {
    pair res;
    res.path = 0;
    res.sig = false;

    if (!g) {
        errno = EINVAL;
        res.path = -1; // path = -1 to flaga na niepoprawny wynik
        return res;
    }

    if (g->calculated) {
        res.path = g->parameters.path;
        res.sig = g->parameters.sig;
        return res; // bramka byla juz policzona w tym wywolaniu nand_evaluate
    } // robimy to aby nie liczyc tego samego segmentu wiele razy w jednym wywolaniu funkcji

    if (g->visited) {
        res.path = -1;
        g->visited = false;
        return res; // bramka byla juz odwiedzona. antypetlik
    }

    if (g->if_sig) { //trafilismy na sygnal boolowski
        res.sig = *(g->val);
        return res;
    }

    g->visited = true;

    for (unsigned i = 0; i < g->n; ++i) {
        pair prev = evaluate(g->inputs[i].gate);
        if (prev.path == -1) {
            res.path = -1;
            g->visited = false;
            g->calculated = true;
            return res;
        }
        if (prev.sig == false) res.sig = true;
        res.path = max(res.path, prev.path + 1);
    }

    g->visited = false;
    g->parameters.path = res.path;
    g->parameters.sig = res.sig;
    g->calculated = true;
    return res;
}

void cleanup(nand_t *g) {
    if (!g) return; // dostalismy bledny argument wiec wracamy
    if (!g->calculated) return; // wszystko glebiej juz wyczyszczone
    g->calculated = false;
    for (unsigned i = 0; i < g->n; ++i) cleanup(g->inputs[i].gate);
}

ssize_t nand_evaluate(nand_t **g, bool *s, size_t m) {
    if (!g || s == NULL || m == 0) {
        errno = EINVAL;
        return -1;
    }

    int final = 0;

    for (unsigned i = 0; i < m; ++i) {
        pair v = evaluate(g[i]);
        if (v.path == -1) {
            errno = ECANCELED;
            for (unsigned j = 0; j < m; ++j) cleanup(g[j]);
            return -1;
        }
        s[i] = v.sig;   
        final = max(final, v.path);
    }

    //czyscimy flage na policzone bramki
    for (unsigned i = 0; i < m; ++i) cleanup(g[i]);

    return final;
}

ssize_t nand_fan_out(nand_t const *g) {
    if (!g) {
        errno = EINVAL;
        return -1;
    }
    return (g->c + 1 - g->nu);
}

void* nand_input(nand_t const *g, unsigned k) {
    if (!g || k >= g->n) {
        errno = EINVAL;
        return NULL;
    }

    if(!g->inputs[k].gate) {
        errno = 0;
        return NULL;
    }

    if (g->inputs[k].gate->if_sig) return (void*)g->inputs[k].gate->val;

    return g->inputs[k].gate;
}

nand_t* nand_output(nand_t const *g, ssize_t k) {
    int i = 0;
    ssize_t s = 0;

    //przechodzimy po dziurach zeby zwrocic k-ta bramke do ktorej przekazujemy sygnal
    while (s <= k && i <= g->c) {
        if(g->pinned_to[i].gate) s += 1;
        i++;
    }

    return g->pinned_to[i - 1].gate;
}
