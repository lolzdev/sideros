#include "vulkan/vulkan.h"

typedef struct {
  VkInstance instance;
  VkSurfaceKHR surface;
} GameInit;

typedef struct {
  double dt;
} GameUpdate;

void sideros_init(GameInit init);
void sideros_update(GameUpdate state);
void sideros_cleanup(void);
