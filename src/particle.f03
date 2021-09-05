module particle
    use mpi
    use constants
    use shared_data
    use math
    implicit none

    !> derived particle type
    type, public :: particle_type
        integer          :: id
        integer          :: global_cell_index_x
        integer          :: global_cell_index_y
        integer          :: global_cell_index_z
        integer          :: procs_rank
        double precision :: mass, charge
        double precision :: pos_x, pos_y, pos_z
        double precision :: vel_x, vel_y, vel_z

        contains

        !> new features in Fortran 2003, allow us to have type bound procedure
        procedure :: kinetic_energy => calculate_kinetic_energy
        procedure :: gamma => calculate_gamma
        procedure :: speed => calculate_speed
        procedure :: rest_energy => calculate_rest_energy
        procedure :: momentum => calculate_momentum
        procedure :: initialize => initialize_particle
    end type particle_type


    !> the list that store global partarticle and local ones
    type(particle_type), dimension(:), allocatable :: global_part_list
    type(particle_type), dimension(:), allocatable :: local_part_list


    contains

    !> caluclate speed of particle
    function calculate_speed(this) result(speed)
        implicit none
        class(particle_type), intent(in) :: this
        double precision :: speed
            speed = dsqrt(this%vel_x**2 + this%vel_y**2 + this%vel_z**2)
    end function calculate_speed


    !> calculate gamma coefficient of the particle
    function calculate_gamma(this) result(gamma)
        implicit none
        class(particle_type), intent(in) :: this
        double precision  ::  gamma
        gamma = 1.d0 / dsqrt(1.d0 - calculate_speed(this)**2/c**2)
    end function calculate_gamma


    !> calculate kinetic energy of the particle
    function calculate_kinetic_energy(this) result(KE)
        implicit none
        class(particle_type), intent(in) :: this
        double precision  ::  KE
        !> relativistic kinetic energy
        KE = (calculate_gamma(this) - 1.d0) * this%mass * c**2 
    end function calculate_kinetic_energy


    !> calculate rest energy of the particle
    function calculate_rest_energy(this) result(rest_energy)
        implicit none
        class(particle_type), intent(in) :: this
        double precision  ::  rest_energy
        !> rest energy
        rest_energy = this%mass * c**2
    end function calculate_rest_energy


    !> calculate relativistic momentum of the particle
    function calculate_momentum(this) result(p)
        implicit none
        class(particle_type), intent(in) :: this
        double precision  ::  p
        p = calculate_gamma(this) * this%mass * calculate_speed(this)
    end function calculate_momentum


    !> initialize particle derived type
    subroutine initialize_particle(this)
        implicit none
        class(particle_type), intent(inout) :: this
        this % id = 0
        this % global_cell_index_x = 0
        this % global_cell_index_y = 0
        this % global_cell_index_z = 0
        this % procs_rank = 0
        this % mass = 0.d0
        this % charge = 0.d0
        this % pos_x = 0.d0
        this % pos_y = 0.d0
        this % pos_z = 0.d0
        this % vel_x = 0.d0
        this % vel_y = 0.d0
        this % vel_z = 0.d0
    end subroutine initialize_particle


    !> load particle into simulation space globally
    subroutine load_particles_globally(ierr)
        implicit none
        integer, intent(inout) :: ierr
        integer                :: i
        integer, allocatable   :: seed(:)
        integer                :: n, clock, j
        double precision       :: trial_x, trial_y, trial_z
        
        !> first allocate global particle list
        allocate(global_part_list(total_particles), stat=ierr)

        !> initialize state of PRNG
        call random_seed(size=n)
        allocate(seed(n))
        call system_clock(count=clock)
        seed = clock + 37 * (/ (j-1, j=1, n) /)
        call random_seed(put=seed)
        deallocate(seed)

        !> initialize all particles
        do i = 1, total_particles
            call global_part_list(i) % initialize
            !> asign id
            global_part_list(i) % id = i
        end do

        !> first load particle position distribution accroding to
        !> density function
        if (particle_distribution == 'uniform_in_domain') then
            do i = 1, total_particles
                global_part_list(i) % pos_x = uniform_distribution(x_min, x_max)
                global_part_list(i) % pos_y = uniform_distribution(y_min, y_max)
                global_part_list(i) % pos_z = uniform_distribution(z_min, z_max)
            end do

        else if (particle_distribution == 'uniform_slab') then
            do i = 1, total_particles
                global_part_list(i) % pos_x = uniform_distribution(slab_xmin, slab_xmax)
                global_part_list(i) % pos_y = uniform_distribution(slab_ymin, slab_ymax)
                global_part_list(i) % pos_z = uniform_distribution(slab_zmin, slab_zmax)
            end do

        else if (particle_distribution == 'gaussian_slab') then
            do i = 1, total_particles
                do 
                    trial_x = gaussian_distribution(slab_center_x, FWHM_x*fwhm2sigma)
                    trial_y = gaussian_distribution(slab_center_y, FWHM_y*fwhm2sigma)
                    trial_z = gaussian_distribution(slab_center_z, FWHM_z*fwhm2sigma)
                    if ((trial_x>=x_min).and.(trial_x<=x_max).and.(trial_y>=y_min).and.&
                        (trial_y<=y_max).and.(trial_z>=z_min).and.(trial_z<=z_max)) then
                            exit
                    end if
                end do
                global_part_list(i) % pos_x = trial_x
                global_part_list(i) % pos_y = trial_y
                global_part_list(i) % pos_z = trial_z
            end do

        else if (particle_distribution == 'double_uniform_slab') then
            do i = 1, total_particles/2
                global_part_list(i) % pos_x = uniform_distribution(slab1_xmin, slab1_xmax)
                global_part_list(i) % pos_y = uniform_distribution(slab1_ymin, slab1_ymax)
                global_part_list(i) % pos_z = uniform_distribution(slab1_zmin, slab1_zmax)
            end do
            do i = total_particles/2+1, total_particles
                global_part_list(i) % pos_x = uniform_distribution(slab2_xmin, slab2_xmax)
                global_part_list(i) % pos_y = uniform_distribution(slab2_ymin, slab2_ymax)
                global_part_list(i) % pos_z = uniform_distribution(slab2_zmin, slab2_zmax)
            end do

        else if (particle_distribution == 'uniform_sphere') then
            do i = 1, total_particles
                do
                    trial_x = uniform_distribution(-sphere_radius, sphere_radius)
                    trial_y = uniform_distribution(-sphere_radius, sphere_radius)
                    trial_z = uniform_distribution(-sphere_radius, sphere_radius)
                    if (dsqrt(trial_x**2+trial_y**2+trial_z**2) <= sphere_radius) then
                            exit
                    end if
                end do
                global_part_list(i) % pos_x = sphere_center_x + trial_x
                global_part_list(i) % pos_y = sphere_center_y + trial_y
                global_part_list(i) % pos_z = sphere_center_z + trial_z
            end do

        else if (particle_distribution == 'custom') then
            !>
            ! use custom fucntion locate in user_custom directory
            ! (add in the future)
            !>
        else
            write(*, *) ' unrecongnized option for particle distribution'
            stop
        end if

        !> load particle velocity distrituion
        if (velocity_distribution == 'cold_xyz') then
            do i = 1, total_particles
                global_part_list(i) % vel_x = 0.d0
                global_part_list(i) % vel_y = 0.d0
                global_part_list(i) % vel_z = 0.d0
            end do
        else if (velocity_distribution == 'maxwell_xyz') then
            do i = 1, total_particles
                global_part_list(i) % vel_x = maxwell_boltzmann(particle_temp_x, particle_mass)
                global_part_list(i) % vel_y = maxwell_boltzmann(particle_temp_y, particle_mass)
                global_part_list(i) % vel_z = maxwell_boltzmann(particle_temp_z, particle_mass)
            end do
        else if (velocity_distribution == 'cold_xy_maxwell_z') then
                global_part_list(i) % vel_x = 0.d0
                global_part_list(i) % vel_y = 0.d0
                global_part_list(i) % vel_z = maxwell_boltzmann(particle_temp_z, particle_mass)
        else if (velocity_distribution == 'cold_xz_maxwell_y') then
                global_part_list(i) % vel_x = 0.d0
                global_part_list(i) % vel_y = maxwell_boltzmann(particle_temp_y, particle_mass)
                global_part_list(i) % vel_z = 0.d0
        else if (velocity_distribution == 'cold_yz_maxwell_x') then
                global_part_list(i) % vel_x = maxwell_boltzmann(particle_temp_x, particle_mass)
                global_part_list(i) % vel_y = 0.d0
                global_part_list(i) % vel_z = 0.d0
        else if (velocity_distribution == 'cold_x_maxwell_yz') then
                global_part_list(i) % vel_x = 0.d0
                global_part_list(i) % vel_y = maxwell_boltzmann(particle_temp_y, particle_mass)
                global_part_list(i) % vel_z = maxwell_boltzmann(particle_temp_z, particle_mass)
        else if (velocity_distribution == 'cold_y_maxwell_xz') then
                global_part_list(i) % vel_x = maxwell_boltzmann(particle_temp_x, particle_mass)
                global_part_list(i) % vel_y = 0.d0
                global_part_list(i) % vel_z = maxwell_boltzmann(particle_temp_z, particle_mass)
        else if (velocity_distribution == 'cold_z_maxwell_xy') then
                global_part_list(i) % vel_x = maxwell_boltzmann(particle_temp_x, particle_mass)
                global_part_list(i) % vel_y = maxwell_boltzmann(particle_temp_y, particle_mass)
                global_part_list(i) % vel_z = 0.d0
        else
            write(*, *) ' unrecongnized option for velocity distribution'
            stop
        end if

        do i = 1, total_particles
            global_part_list(i) % mass = particle_mass
            global_part_list(i) % charge = particle_charge
        end do
    end subroutine load_particles_globally


    !> unload particle globally
    subroutine unload_particles_globally(ierr)
        implicit none
        integer, intent(inout) :: ierr
        
        deallocate(global_part_list, stat=ierr)
    end subroutine unload_particles_globally


    !> unload particle locally
    subroutine unload_particles_locally(ierr)
        implicit none
        integer, intent(inout) :: ierr
        
        deallocate(local_part_list, stat=ierr)
    end subroutine unload_particles_locally


    !> map particle in global cell using auxi cell
    function map_particle_to_global_cell(pos_x, pos_y, pos_z)
        implicit none
        integer, dimension(3)        :: map_particle_to_global_cell
        double precision, intent(in) :: pos_x, pos_y, pos_z
        ! double precision             :: wx, wy, wz
        integer                      :: auxi_x, auxi_y, auxi_z
        integer                      :: procs_id

        ! wx = (x_max - x_min) / dble(numprocs_x)
        ! wy = (y_max - y_min) / dble(numprocs_y)
        ! wz = (z_max - z_min) / dble(numprocs_z)
        ! map_particle_to_global_cell(1) = floor((pos_x - x_min) / wx) + 1
        ! map_particle_to_global_cell(2) = floor((pos_y - y_min) / wy) + 1
        ! map_particle_to_global_cell(3) = floor((pos_z - z_min) / wz) + 1

        auxi_x = floor((pos_x / auxi_cell_wx)) + 1
        auxi_y = floor((pos_y / auxi_cell_wy)) + 1
        auxi_z = floor((pos_z / auxi_cell_wz)) + 1

        !> get processor id
        procs_id = auxi_cell(auxi_x, auxi_y, auxi_z, 4)

        !> from processor id to rank (x, y, z)
        map_particle_to_global_cell(1) = auxi_cell(auxi_x, auxi_y, auxi_z, 1)
        map_particle_to_global_cell(2) = auxi_cell(auxi_x, auxi_y, auxi_z, 2)
        map_particle_to_global_cell(3) = auxi_cell(auxi_x, auxi_y, auxi_z, 3)

    end function map_particle_to_global_cell


end module particle